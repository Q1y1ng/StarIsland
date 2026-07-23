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
/// ├──────────────────────────────────┤
/// │                   📍             │
/// │          MAP (fixed pin)         │
/// │                                  │
/// ├──────────────────────────────────┤
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
    @State private var selectedPlace: NearbyPlace?
    @State private var isFetchingCurrentLocation = false
    @State private var searchTask: Task<Void, Never>?
    @State private var nearbySearchTask: Task<Void, Never>?
    @State private var isSearching = false

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
        if let lat = selectedLatitude.wrappedValue,
           let lng = selectedLongitude.wrappedValue {
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )))
        } else {
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 34.3416, longitude: 108.9398),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )))
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // ── Map layer ──────────────────────────────────────────
                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, AppTheme.spacing.xlarge)
                        .padding(.vertical, AppTheme.spacing.medium)

                    ZStack {
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
                        .onMapCameraChange(frequency: .onEnd) { context in
                            let center = context.region.center
                            // Clear selection when user manually drags the map
                            selectedPlace = nil
                            Task { await fetchNearbyPlaces(center: center) }
                        }

                        // Fixed center pin — always stays at map center
                        Image(systemName: "mappin")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .offset(y: -16)
                    }
                }

                // ── Bottom Sheet ───────────────────────────────────────
                bottomSheet
            }
            .navigationTitle("选择位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
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
            // Initial nearby fetch
            if case .region(let region) = cameraPosition {
                Task { await fetchNearbyPlaces(center: region.center) }
            }
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

    // MARK: - Bottom Sheet

    private var bottomSheet: some View {
        VStack(spacing: 0) {
            // ── Drag handle ───────────────────────────────────────────
            Capsule()
                .fill(.tertiary)
                .frame(width: 36, height: 5)
                .padding(.vertical, 8)

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
            .padding(.bottom, AppTheme.spacing.small)

            // ── Places list ───────────────────────────────────────────
            if currentPlaces.isEmpty && !isSearching {
                Text(isSearchActive ? "未找到地点" : "拖动地图查找附近地点")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing.large)
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
                .frame(maxHeight: 260)
            }

            // ── Current location ──────────────────────────────────────
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

            // ── Confirm button ────────────────────────────────────────
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
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Actions

    private func selectPlace(_ place: NearbyPlace) {
        selectedPlace = place

        // Animate map to center on the selected place
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
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                    // onMapCameraChange(.onEnd) will trigger nearby fetch
                }
                isFetchingCurrentLocation = false
            }
        }
    }

    // MARK: - Nearby Places (MKLocalSearch)

    /// Fetch nearby POIs around `center` using MKLocalSearch.
    /// 1. Reverse geocode to get locality hint.
    /// 2. MKLocalSearch with the locality as query, ~300m radius.
    /// 3. Sort results by distance from center.
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

        // 2. Search nearby POIs
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
            // MKPlacemark.coordinate is always valid for MKLocalSearch results
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

        // Scope search to current map region
        if case .region(let region) = cameraPosition {
            request.region = region
        } else {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 34.3416, longitude: 108.9398),
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            )
        }

        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), !Task.isCancelled else { return }

        // Calculate distance from map center
        let centerLocation: CLLocation
        if case .region(let region) = cameraPosition {
            centerLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        } else {
            centerLocation = CLLocation(latitude: 34.3416, longitude: 108.9398)
        }

        let places = response.mapItems
            // MKPlacemark.coordinate is always valid for MKLocalSearch results
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
                .foregroundStyle(isSelected ? .blue : .tertiary)
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
