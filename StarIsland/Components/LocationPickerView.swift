import SwiftUI
import MapKit
import CoreLocation

// MARK: - Nearby Place

/// A POI returned from MKLocalSearch, enriched with distance from map center.
struct NearbyPlace: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance
    let placemark: CLPlacemark
    let mapItem: MKMapItem

    var distanceFormatted: String {
        if distance < 1000 {
            return "\(Int(distance))m"
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
}

// MARK: - Location Picker View

/// Apple Maps‑style location picker.
///
/// ```
/// ┌──────────────────────────────────┐
/// │  [🔍 搜索地点]                    │
/// │                   📍             │
/// │          MAP (full screen)       │
/// │                                  │
/// ├──────────────────────────────────┤  ← sheet (draggable)
/// │  ───                             │
/// │  附近地点                         │
/// │  · 逸景雅居                100m  │
/// │  · 林河世家                120m  │
/// │  · 鹿原温泉小区            150m  │
/// │  [📍 当前位置]                    │
/// │  [确定]                          │
/// └──────────────────────────────────┘
/// ```
///
/// Uses only Apple native frameworks: MapKit, CoreLocation, CLGeocoder,
/// MKLocalSearch.  No third‑party SDKs.
///
/// # Single source of truth
/// ``mapCenter`` is the **only** coordinate source for nearby search,
/// reverse geocode, and POI search.  It is updated on every
/// ``onMapCameraChange(frequency: .continuous)`` callback.  All other
/// coordinate values (first‑fetch location, current‑location button,
/// selected‑place coordinate) are used exclusively for map positioning
/// and record saving — never as input to ``MKLocalSearch``.
struct LocationPickerView: View {
    @Binding var selectedName: String?
    @Binding var selectedLatitude: Double?
    @Binding var selectedLongitude: Double?
    @Binding var selectedPlacemark: CLPlacemark?

    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var nearbyPlaces: [NearbyPlace] = []
    @State private var searchResults: [NearbyPlace] = []
    @State private var cameraPosition: MapCameraPosition
    @State private var mapCenter: CLLocationCoordinate2D
    @State private var selectedPlace: NearbyPlace?
    @State private var isFetchingCurrentLocation = false
    @State private var searchTask: Task<Void, Never>?
    @State private var nearbySearchTask: Task<Void, Never>?
    @State private var isSearching = false
    @State private var isSheetPresented = true

    private let locationService = LocationService.shared

    /// Whether the user has typed something in the search bar.
    private var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The list currently shown: search results when active, nearby places otherwise.
    private var currentPlaces: [NearbyPlace] {
        isSearchActive ? searchResults : nearbyPlaces
    }

    // MARK: - Init

    init(selectedName: Binding<String?>,
         selectedLatitude: Binding<Double?>,
         selectedLongitude: Binding<Double?>,
         selectedPlacemark: Binding<CLPlacemark?>) {
        self._selectedName = selectedName
        self._selectedLatitude = selectedLatitude
        self._selectedLongitude = selectedLongitude
        self._selectedPlacemark = selectedPlacemark

        // Start at existing location or default to Xi'an
        let initialCenter: CLLocationCoordinate2D
        if let lat = selectedLatitude.wrappedValue,
           let lng = selectedLongitude.wrappedValue {
            initialCenter = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: initialCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )))
        } else {
            initialCenter = CLLocationCoordinate2D(latitude: 34.3416, longitude: 108.9398)
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: initialCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )))
        }
        _mapCenter = State(initialValue: initialCenter)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                // Marker at selected place
                if let place = selectedPlace {
                    Marker(place.name, coordinate: place.coordinate)
                }
            }
            .mapStyle(.standard)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                // ── Single source of truth ──────────────────────────
                mapCenter = context.region.center

                // ── Debounced nearby search ────────────────────────
                nearbySearchTask?.cancel()
                nearbySearchTask = Task { [center = context.region.center] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await fetchNearbyPlaces(center: center)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { _ in
                // User finished dragging — clear previous selection
                selectedPlace = nil
            }
            .overlay(alignment: .center) {
                // Fixed center pin — always stays at map center
                Image(systemName: "mappin")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .offset(y: -16)
            }
            .overlay(alignment: .top) {
                searchBar
                    .padding(.horizontal, AppTheme.spacing.xlarge)
                    .padding(.vertical, AppTheme.spacing.medium)
            }
            .navigationTitle("选择位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $isSheetPresented) {
                bottomSheetContent
                    .presentationDetents([.fraction(0.28), .medium, .large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    await MainActor.run { searchResults = [] }
                } else {
                    await performSearch(query: newValue)
                }
            }
        }
        .onAppear {
            // Initial nearby fetch (uses mapCenter set in init)
            Task { await fetchNearbyPlaces(center: mapCenter) }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: AppTheme.spacing.medium) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)

            TextField("搜索地点", text: $searchQuery)
                .font(.subheadline)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await performSearch(query: searchQuery) } }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, AppTheme.spacing.medium)
        .padding(.vertical, AppTheme.spacing.small)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Bottom Sheet Content

    /// Content shown inside the draggable sheet.
    /// The sheet has ``presentationDetents`` so the user can drag between
    /// `.fraction(0.28)`, `.medium`, and `.large`.
    private var bottomSheetContent: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────
            HStack {
                Text(isSearchActive ? "搜索结果" : "附近地点")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if isSearching {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, AppTheme.spacing.xlarge)
            .padding(.top, AppTheme.spacing.medium)
            .padding(.bottom, AppTheme.spacing.small)

            // ── Places list ───────────────────────────────────────────
            if currentPlaces.isEmpty && !isSearching {
                Spacer()
                Text(isSearchActive ? "未找到地点" : "拖动地图查找附近地点")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(currentPlaces) { place in
                            PlaceRow(
                                place: place,
                                isSelected: selectedPlace?.id == place.id
                            )
                            .onTapGesture { selectPlace(place) }

                            if place.id != currentPlaces.last?.id {
                                Divider()
                                    .padding(.leading, AppTheme.spacing.xlarge)
                            }
                        }
                    }
                }
            }

            // ── Current location + Confirm ────────────────────────────
            VStack(spacing: 0) {
                Divider()
                    .padding(.horizontal, AppTheme.spacing.xlarge)

                Button {
                    fetchCurrentLocation()
                } label: {
                    HStack(spacing: AppTheme.spacing.medium) {
                        Image(systemName: "location.fill")
                            .font(.subheadline)
                        Text("当前位置")
                            .font(.subheadline)
                        if isFetchingCurrentLocation {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.spacing.xlarge)
                    .padding(.vertical, AppTheme.spacing.medium)
                }
                .disabled(isFetchingCurrentLocation)

                Button(action: confirmSelection) {
                    Text("确定")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedPlace != nil ? Color.blue : Color.blue.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(selectedPlace == nil)
                .padding(.horizontal, AppTheme.spacing.xlarge)
                .padding(.bottom, AppTheme.spacing.medium)
            }
        }
        .background(.regularMaterial)
    }

    // MARK: - Actions

    private func selectPlace(_ place: NearbyPlace) {
        selectedPlace = place

        // Animate map to center on the selected place
        // This triggers onMapCameraChange(.continuous) which updates
        // mapCenter and starts a debounced nearby search.  Since
        // onMapCameraChange(.onEnd) only fires after gesture end
        // (not programmatic animation), selectedPlace is preserved.
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: place.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }
    }

    private func confirmSelection() {
        guard let place = selectedPlace else { return }

        selectedName = place.name
        selectedLatitude = place.coordinate.latitude
        selectedLongitude = place.coordinate.longitude
        selectedPlacemark = place.placemark
        dismiss()
    }

    private func fetchCurrentLocation() {
        isFetchingCurrentLocation = true
        Task {
            let result = await locationService.requestLocation()
            await MainActor.run {
                if let lat = result.latitude, let lng = result.longitude {
                    // Clear any previous selection — map is moving to a new center
                    selectedPlace = nil
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                    // onMapCameraChange(.continuous) + 300ms debounce
                    // will trigger nearby search with the new mapCenter
                }
                isFetchingCurrentLocation = false
            }
        }
    }

    // MARK: - Nearby Places (MKLocalSearch)

    /// Fetch nearby POIs around `center` using MKLocalSearch.
    ///
    /// 1. Reverse geocode to get locality hint.
    /// 2. MKLocalSearch with the locality as query, ~300m radius.
    /// 3. Sort results by distance from center.
    ///
    /// - Parameter center: **Must** be ``mapCenter`` — this is the single
    ///   source of truth for all coordinate-based queries.
    private func fetchNearbyPlaces(center: CLLocationCoordinate2D) async {
        isSearching = true
        defer { isSearching = false }

        // 1. Reverse geocode for locality context
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: center.latitude, longitude: center.longitude)

        let locality: String? = await {
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            return placemarks?.first?.subLocality ?? placemarks?.first?.locality
        }()

        // 2. Search nearby POIs using mapCenter as the sole coordinate source
        let request = MKLocalSearch.Request()
        if let locality, !locality.isEmpty {
            request.naturalLanguageQuery = locality
        }
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 300,
            longitudinalMeters: 300
        )
        request.resultTypes = [.pointOfInterest]

        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), !Task.isCancelled else { return }

        // 3. Build NearbyPlace array sorted by distance
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let places = response.mapItems
            .map { item -> NearbyPlace in
                let coord = item.placemark.coordinate
                let itemLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let distance = centerLocation.distance(from: itemLocation)
                return NearbyPlace(
                    name: item.name ?? "未知地点",
                    coordinate: coord,
                    distance: distance,
                    placemark: item.placemark,
                    mapItem: item
                )
            }
            .sorted { $0.distance < $1.distance }

        await MainActor.run {
            guard !Task.isCancelled else { return }
            nearbyPlaces = places
        }
    }

    // MARK: - Search (MKLocalSearch)

    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            await MainActor.run { searchResults = [] }
            return
        }

        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.pointOfInterest, .address]

        // Scope search to current map region using mapCenter (single source of truth)
        request.region = MKCoordinateRegion(
            center: mapCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )

        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), !Task.isCancelled else { return }

        // Calculate distance from map center
        let centerLocation = CLLocation(latitude: mapCenter.latitude, longitude: mapCenter.longitude)

        let places = response.mapItems
            .map { item -> NearbyPlace in
                let coord = item.placemark.coordinate
                let itemLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let distance = centerLocation.distance(from: itemLocation)
                return NearbyPlace(
                    name: item.name ?? "未知地点",
                    coordinate: coord,
                    distance: distance,
                    placemark: item.placemark,
                    mapItem: item
                )
            }

        await MainActor.run {
            guard !Task.isCancelled else { return }
            searchResults = places
        }
    }
}

// MARK: - Place Row

private struct PlaceRow: View {
    let place: NearbyPlace
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppTheme.spacing.medium) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "mappin.circle")
                .foregroundStyle(isSelected ? .blue : Color.secondary.opacity(0.3))
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(.primary)

                Text(place.distanceFormatted)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, AppTheme.spacing.xlarge)
        .padding(.vertical, AppTheme.spacing.small)
        .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    LocationPickerView(
        selectedName: .constant(nil),
        selectedLatitude: .constant(nil),
        selectedLongitude: .constant(nil),
        selectedPlacemark: .constant(nil)
    )
}
