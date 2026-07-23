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

// MARK: - Sheet Detent

/// Three-tier bottom‑sheet detent matching Apple Maps / 微信发送位置.
private enum SheetDetent: CGFloat, CaseIterable {
    case small  = 0.25
    case medium = 0.50
    case large  = 0.85
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
/// # Single source of truth
/// ``mapCenter`` is the **only** coordinate source for nearby search,
/// reverse geocode, and POI search — guaranteed by self‑check.
///
/// # States & flow
/// - **Map drag** → `onMapCameraChange(.continuous)` → updates ``mapCenter``
///   → 300 ms debounce → ``fetchNearbyPlaces(center:)`` → replaces ``nearbyPlaces``.
/// - **Tap POI** → ``selectPlace(_:)`` → sets ``selectedPlace`` (immediate),
///   animates camera, sets ``isAnimatingToPlace`` so .continuous skips search.
/// - **当前位置** → ``fetchCurrentLocation()`` → updates ``mapCenter`` + ``cameraPosition``
///   directly, triggers immediate search (no debounce), blocks .continuous via flag.
/// - **Search** → text input → 300 ms debounce → ``performSearch(query:)``.
///
/// # Gesture isolation
/// - `Map`: always interactive — no transparent view covers it.
/// - `searchBar`: `.overlay(alignment: .top)` on Map, natural height only.
/// - `bottomPanel`: custom ZStack overlay, drag gesture **only** on capsule handle.
struct LocationPickerView: View {
    @Binding var selectedName: String?
    @Binding var selectedLatitude: Double?
    @Binding var selectedLongitude: Double?
    @Binding var selectedPlacemark: CLPlacemark?

    @Environment(\.dismiss) private var dismiss

    // ── Search & places ──────────────────────────────────────────
    @State private var searchQuery = ""
    @State private var nearbyPlaces: [NearbyPlace] = []
    @State private var searchResults: [NearbyPlace] = []

    // ── Map ──────────────────────────────────────────────────────
    @State private var cameraPosition: MapCameraPosition
    /// **Single** source of truth for all coordinate‑based queries.
    @State private var mapCenter: CLLocationCoordinate2D
    /// Currently selected place (set on tap, cleared on map drag).
    @State private var selectedPlace: NearbyPlace?

    // ── Fetch state ──────────────────────────────────────────────
    @State private var isFetchingCurrentLocation = false
    @State private var searchTask: Task<Void, Never>?
    @State private var nearbySearchTask: Task<Void, Never>?
    @State private var isSearching = false

    /// `true` while a programmatic camera animation is in progress
    /// (triggered by tapping a POI or using 当前位置). During this window the
    /// ``onMapCameraChange(frequency:.continuous)`` handler skips the nearby
    /// search — the map is moving because the user *selected* something,
    /// not because they dragged.
    @State private var isAnimatingToPlace = false

    // ── Bottom sheet ────────────────────────────────────────────
    @State private var sheetDetent: SheetDetent = .small
    @State private var sheetDragOffset: CGFloat = 0

    // ── Convenience ──────────────────────────────────────────────
    private let locationService = LocationService.shared

    private var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The list currently shown: search results when active, nearby places otherwise.
    private var currentPlaces: [NearbyPlace] {
        isSearchActive ? searchResults : nearbyPlaces
    }

    /// Current sheet height after applying the active detent and live drag offset.
    private var sheetHeight: CGFloat {
        let screen = UIScreen.main.bounds.height
        let raw = screen * sheetDetent.rawValue
        return max(screen * SheetDetent.small.rawValue, raw - sheetDragOffset)
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
            // ── Three independent layers ──────────────────────────
            // Layer 1: Map    (full screen, always interactive)
            // Layer 2: Header (search bar, cancel button)
            // Layer 3: Sheet  (bottom panel, draggable handle)
            ZStack(alignment: .bottom) {
                mapLayer
                bottomPanel
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("选择位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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
            // ── Update single source of truth ─────────────────
            mapCenter = context.region.center

            // ── Skip search during programmatic animation ─────
            // selectPlace or fetchCurrentLocation set this flag.
            if isAnimatingToPlace { return }

            // ── Debounced nearby search on user drag ──────────
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
            // User finished dragging map — clear previous selection.
            // onEnd does NOT fire after programmatic animation
            // (cameraPosition assignments without withAnimation do not
            //  trigger onEnd; withAnimation does, but isAnimatingToPlace
            //  guards it).
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
    /// - Drag the **handle**  ↕  to cycle through 3 detents (25 % / 50 % / 85 %).
    /// - **Scroll** the places list independently.
    /// - **Drag / zoom / rotate** the map in the uncovered area.
    ///
    /// The panel is flush with the bottom safe area — only top corners are
    /// rounded, matching Apple Maps / 微信发送位置.
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
                VStack(spacing: 4) {
                    Spacer()
                    Text(isSearchActive ? "未找到地点" : "拖动地图查找附近地点")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
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
        // Only top corners are rounded — bottom is flush with screen edge
        .clipShape(UnevenRoundedRectangle(
            topLeading: 16,
            bottomLeading: 0,
            bottomTrailing: 0,
            topTrailing: 16,
            style: .continuous
        ))
        .zIndex(50)
    }

    /// Drag gesture on the capsule handle — avoids conflicts with both
    /// the ``ScrollView`` and the ``Map`` gestures underneath.
    ///
    /// Snaps to the nearest detent on release, with velocity boost.
    private var sheetDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                sheetDragOffset = value.translation.height
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height
                sheetDragOffset = 0

                let allDetents = SheetDetent.allCases.sorted { $0.rawValue < $1.rawValue }
                let currentFraction = sheetDetent.rawValue

                let target: SheetDetent
                if velocity > 300 {
                    // Fast swipe down → previous (smaller) detent
                    let idx = allDetents.firstIndex(of: sheetDetent) ?? 1
                    target = idx > 0 ? allDetents[idx - 1] : allDetents[0]
                } else if velocity < -300 {
                    // Fast swipe up → next (larger) detent
                    let idx = allDetents.firstIndex(of: sheetDetent) ?? 1
                    target = idx < allDetents.count - 1 ? allDetents[idx + 1] : allDetents.last!
                } else {
                    // Snapping: use drag offset to determine direction
                    let offsetFraction = sheetDragOffset / UIScreen.main.bounds.height
                    let proposed = currentFraction - offsetFraction
                    // Clamp and find nearest detent
                    target = allDetents.min(by: {
                        abs($0.rawValue - proposed) < abs($1.rawValue - proposed)
                    }) ?? sheetDetent
                }

                withAnimation(.interactiveSpring()) {
                    sheetDetent = target
                }
            }
    }

    // MARK: - Actions

    /// Called when the user taps a place in the list.
    ///
    /// Sets ``selectedPlace`` immediately (one‑tap selection).
    /// Sets ``isAnimatingToPlace`` so the ``.continuous`` camera handler
    /// skips the nearby search — the map is moving because the user
    /// *selected* something, not because they dragged.
    ///
    /// Never triggers MKLocalSearch, reverse geocode, or nearby refresh.
    private func selectPlace(_ place: NearbyPlace) {
        selectedPlace = place
        isAnimatingToPlace = true

        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: place.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }

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

    /// Request current device location, move the map there, and refresh
    /// nearby places immediately.
    ///
    /// Flow:
    /// 1. `LocationService.requestLocation()`
    /// 2. Update ``mapCenter`` directly (single source of truth).
    /// 3. Set ``isAnimatingToPlace`` to block .continuous search.
    /// 4. Move ``cameraPosition``.
    /// 5. Call ``fetchNearbyPlaces(center:)` — not debounced.
    /// 6. Reset ``isAnimatingToPlace`` when search completes.
    private func fetchCurrentLocation() {
        isFetchingCurrentLocation = true
        Task {
            let result = await locationService.requestLocation()
            await MainActor.run {
                guard let lat = result.latitude, let lng = result.longitude else {
                    isFetchingCurrentLocation = false
                    return
                }

                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)

                // ── Single source of truth ────────────────────────
                mapCenter = coord
                isAnimatingToPlace = true

                cameraPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))

                // ── Immediate search (not debounced) ─────────────
                nearbySearchTask?.cancel()
                nearbySearchTask = Task {
                    await fetchNearbyPlaces(center: coord)
                    await MainActor.run { isAnimatingToPlace = false }
                }

                selectedPlace = nil
                isFetchingCurrentLocation = false
            }
        }
    }

    // MARK: - Nearby Places (MKLocalSearch)

    /// **Only** entry point for nearby‑place search.
    ///
    /// 1. Reverse geocode ``center`` for locality context.
    /// 2. MKLocalSearch with locality as query + 500 m region.
    /// 3. **No** `resultTypes` filter — uses Apple default behavior,
    ///    which returns a mixed set of residential, commercial,
    ///    food, education, healthcare, transport, etc.
    /// 4. Sort results by **distance from center** (ascending).
    ///
    /// - Parameter center: **Must** be ``mapCenter`` — guaranteed by caller.
    private func fetchNearbyPlaces(center: CLLocationCoordinate2D) async {
        isSearching = true
        defer { isSearching = false }

        // 1. Reverse geocode for locality context
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let locality: String? = await {
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            return placemarks?.first?.locality ?? placemarks?.first?.subLocality
        }()

        // 2. MKLocalSearch — Apple default result types (not filtered)
        let request = MKLocalSearch.Request()
        if let locality, !locality.isEmpty {
            request.naturalLanguageQuery = locality
        }
        // Broader region for comprehensive residential + commercial results
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        // ⚠️  Do NOT set resultTypes — let Apple return its default mix:
        //     residential, commercial, food, education, healthcare, transport, etc.
        //     Setting .pointOfInterest was the root cause of government‑heavy results.

        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), !Task.isCancelled else { return }

        // 3. Build sorted NearbyPlace array by distance from center
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let places: [NearbyPlace] = response.mapItems
            .compactMap { item in
                guard let name = item.name else { return nil }
                let coord = item.placemark.coordinate
                let itemLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let distance = centerLocation.distance(from: itemLocation)
                return NearbyPlace(
                    name: name,
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
        request.region = MKCoordinateRegion(
            center: mapCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )

        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), !Task.isCancelled else { return }

        // Calculate distance from map center for consistent sorting
        let centerLocation = CLLocation(latitude: mapCenter.latitude, longitude: mapCenter.longitude)
        let places = response.mapItems
            .compactMap { item -> NearbyPlace? in
                guard let name = item.name else { return nil }
                let coord = item.placemark.coordinate
                let itemLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let distance = centerLocation.distance(from: itemLocation)
                return NearbyPlace(
                    name: name,
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
