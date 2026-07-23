import SwiftUI
import MapKit
import CoreLocation

// MARK: - Nearby Place

/// A POI returned from MKLocalSearch, enriched with distance from map center.
struct NearbyPlace: Identifiable {
    /// Stable identifier based on name + coordinate,
    /// so that ``selectedPlace`` is preserved across list refreshes.
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance
    let placemark: CLPlacemark
    let mapItem: MKMapItem

    init(
        name: String,
        coordinate: CLLocationCoordinate2D,
        distance: CLLocationDistance,
        placemark: CLPlacemark,
        mapItem: MKMapItem
    ) {
        // Build a stable ID so the same POI is recognised after a list refresh
        let latStr = String(format: "%.5f", coordinate.latitude)
        let lngStr = String(format: "%.5f", coordinate.longitude)
        self.id = "\(name)-\(latStr)-\(lngStr)"
        self.name = name
        self.coordinate = coordinate
        self.distance = distance
        self.placemark = placemark
        self.mapItem = mapItem
    }

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
/// │          freely draggable        │
/// ├──────────────────────────────────┤  ← bottom panel (draggable)
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
/// reverse geocode, and POI search.
///
/// # Interaction rules
/// - **Map drag / zoom / rotate**: fully interactive — no view covers the map.
/// - **Bottom panel**: custom overlay (not `.sheet`) so the map stays live.
/// - **Tap POI**: sets ``selectedPlace`` immediately, does NOT re-search.
/// - **Nearby search**: only fires on map‑center change (debounced 300ms).
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

    /// `true` while a programmatic camera animation is in progress
    /// (triggered by tapping a POI).  During this window the
    /// ``onMapCameraChange(frequency:.continuous)`` handler skips the nearby
    /// search — the map is moving because the user *selected* something,
    /// not because they dragged.
    @State private var isAnimatingToPlace = false

    /// Bottom‑panel drag state
    @State private var sheetDragOffset: CGFloat = 0
    @State private var isSheetExpanded = false

    private let locationService = LocationService.shared

    private let minSheetHeight: CGFloat = 280
    private var maxSheetHeight: CGFloat { UIScreen.main.bounds.height * 0.7 }

    /// Whether the user has typed something in the search bar.
    private var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The list currently shown: search results when active, nearby places otherwise.
    private var currentPlaces: [NearbyPlace] {
        isSearchActive ? searchResults : nearbyPlaces
    }

    /// Current height of the bottom panel (before drag offset is applied).
    private var baseSheetHeight: CGFloat {
        isSheetExpanded ? maxSheetHeight : minSheetHeight
    }

    /// Final panel height after applying live drag offset.
    private var sheetHeight: CGFloat {
        max(minSheetHeight, baseSheetHeight - sheetDragOffset)
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
            ZStack(alignment: .bottom) {
                // ════════════════════════════════════════════════════════
                // Layer 1 — Map (full screen, fully interactive)
                // The search bar is an overlay ON the map so it only
                // occupies its natural height — no full‑screen blocker.
                // ════════════════════════════════════════════════════════
                mapLayer

                // ════════════════════════════════════════════════════════
                // Layer 2 — Bottom panel (overlay, draggable handle)
                // ════════════════════════════════════════════════════════
                bottomPanel
            }
            .navigationTitle("选择位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .zIndex(100) // ensure tappable above everything
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
            // Initial nearby fetch (uses mapCenter set in init)
            Task { await fetchNearbyPlaces(center: mapCenter) }
        }
    }

    // MARK: - Map Layer

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
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
            mapCenter = context.region.center

            // ── Do NOT search during programmatic animation (Bug 4) ──
            if isAnimatingToPlace { return }

            // ── Debounced nearby search on user drag ──────────────
            nearbySearchTask?.cancel()
            nearbySearchTask = Task { [center = context.region.center] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let shouldSearch = await MainActor.run { !isAnimatingToPlace }
                guard shouldSearch else { return }
                await fetchNearbyPlaces(center: center)
            }
        }
        .onMapCameraChange(frequency: .onEnd) { _ in
            // User finished dragging — clear previous selection
            // (onEnd does NOT fire after programmatic animation)
            if !isAnimatingToPlace {
                selectedPlace = nil
            }
        }
        .overlay(alignment: .center) {
            // Fixed center pin — visual only, never blocks map gestures
            Image(systemName: "mappin")
                .font(.title2)
                .foregroundStyle(.blue)
                .offset(y: -16)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            searchBar
                .padding(.horizontal, AppTheme.spacing.xlarge)
                .padding(.top, AppTheme.spacing.medium)
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

    // MARK: - Bottom Panel

    /// Custom bottom panel (not a `.sheet`!) so the map remains fully
    /// interactive behind it.  The user can:
    /// - Drag the **handle**  ↕  to expand / collapse the panel.
    /// - **Scroll** the places list independently.
    /// - **Drag / zoom / rotate** the map in the uncovered area.
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // ── Drag handle ───────────────────────────────────────
            Capsule()
                .fill(.tertiary)
                .frame(width: 36, height: 5)
                .padding(.vertical, 8)
                .gesture(sheetDragGesture)
                .zIndex(10)

            // ── Header ────────────────────────────────────────────
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

            // ── Places list ───────────────────────────────────────
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

            // ── Current location + Confirm ────────────────────────
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
        .frame(height: sheetHeight)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .zIndex(50)
    }

    /// Drag gesture placed on the capsule handle so it does not conflict
    /// with the ``ScrollView`` or the ``Map`` gestures underneath.
    private var sheetDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                sheetDragOffset = value.translation.height
            }
            .onEnded { value in
                let offset = sheetDragOffset
                let velocity = value.predictedEndTranslation.height
                sheetDragOffset = 0

                withAnimation(.interactiveSpring()) {
                    if isSheetExpanded {
                        // Collapse when dragged down past threshold
                        if offset > 80 || velocity > 200 {
                            isSheetExpanded = false
                        }
                        // otherwise stay expanded
                    } else {
                        // Expand when dragged up past threshold
                        if offset < -80 || velocity < -200 {
                            isSheetExpanded = true
                        }
                        // otherwise stay compact
                    }
                }
            }
    }

    // MARK: - Actions

    /// Called when the user taps a place in the list.
    ///
    /// Sets ``selectedPlace`` immediately (one‑tap selection, Bug 3).
    /// Sets ``isAnimatingToPlace`` so the ``.continuous`` camera handler
    /// skips the nearby search — the map is moving because the user
    /// *selected* something, not because they dragged (Bug 4).
    private func selectPlace(_ place: NearbyPlace) {
        selectedPlace = place
        isAnimatingToPlace = true

        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: place.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }

        // Reset flag after animation completes (debounce window included)
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            await MainActor.run { isAnimatingToPlace = false }
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
                    selectedPlace = nil
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
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
    /// - Parameter center: **Must** be ``mapCenter`` — the single
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
