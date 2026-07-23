import SwiftUI
import MapKit
import CoreLocation

// MARK: - Nearby Place

/// A POI returned from Apple MapKit POI Search, enriched with distance from map center.
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

// MARK: - Administrative Region Filter

/// Checks whether a ``MKMapItem`` represents an administrative division
/// (市／区／县／省／镇) rather than a real POI such as a shop, restaurant,
/// school, hospital, or park.
///
/// Uses two signals:
/// 1. The item's name matches one of the placemark's administrative‑area fields.
/// 2. The name ends with an administrative suffix (市／区／县／省／镇) and is short.
private func isAdministrativeRegion(item: MKMapItem) -> Bool {
    guard let name = item.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
        return false
    }

    let pm = item.placemark

    // ── Signal 1: name matches a known admin division ──────────────
    let adminFields: [String?] = [
        pm.administrativeArea,       // 陕西省
        pm.subAdministrativeArea,    // 西安市 (prefecture-level)
        pm.locality,                 // 西安市
        pm.subLocality,              // 灞桥区
    ]
    if adminFields.compactMap({ $0 }).contains(where: { $0 == name }) {
        return true
    }

    // ── Signal 2: name looks like an administrative label ──────────
    let adminSuffixes = ["市", "区", "县", "省", "镇", "乡"]
    if name.count <= 8,
       adminSuffixes.contains(where: { name.hasSuffix($0) }) {
        return true
    }

    return false
}

// MARK: - Search Radius

/// Computes a POI search radius (in meters) from the visible map region.
/// Clamped between 1 000 m (default minimum) and 2 000 m (city view).
/// A larger minimum radius ensures MKLocalSearch returns sufficient results
/// even in areas with moderate POI density.
private func searchRadius(from region: MKCoordinateRegion) -> CLLocationDistance {
    let midLat = region.center.latitude * .pi / 180
    let metersPerDegreeLat: CLLocationDistance = 111_320
    let metersPerDegreeLng: CLLocationDistance = 111_320 * cos(midLat)
    let widthMeters = region.span.longitudeDelta * metersPerDegreeLng
    let heightMeters = region.span.latitudeDelta * metersPerDegreeLat
    let avgDimension = (abs(widthMeters) + abs(heightMeters)) / 2
    return min(max(avgDimension / 2, 1_000), 2_000)
}

// MARK: - POI Category Filter

/// All POI categories are included in nearby‑place searches.
/// Administrative divisions (市／区／县／省) are still filtered out
/// by ``isAdministrativeRegion(item:)`` as a post‑processing step.
private let nearbyPOIFilter = MKPointOfInterestFilter.includingAll

// MARK: - Sheet Detent

/// Two‑tier bottom‑sheet detent matching Apple Maps:
/// - small  (≈ 35 %) — default, shows nearby places
/// - large  (≈ 90 %) — expanded, for browsing the full list
private enum SheetDetent: CGFloat, CaseIterable {
    case small = 0.35
    case large = 0.90
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
/// │  附近地点 / 搜索结果               │
/// │  · 逸景雅居                100m  │
/// │  · 林河世家                120m  │
/// │  · 鹿原温泉小区            150m  │
/// │  [📍 当前位置]                    │
/// │  [确定]                          │
/// └──────────────────────────────────┘
/// ```
///
/// # Architecture
///
/// ``mapCenter`` is the **single source of truth** for all coordinate‑based
/// queries — nearby POI search, text search, reverse geocode.  It is updated
/// exclusively by ``onMapCameraChange(frequency: .continuous)`` and by
/// ``fetchCurrentLocation()``. No other path writes to it.
///
/// # Search strategy
///
/// - **Nearby POI search** (map drag → camera idle → 300 ms debounce):
///   Uses ``MKLocalSearch`` with ``MKLocalPointsOfInterestRequest``
///   (iOS 16+ official POI‑only search API — no ``naturalLanguageQuery``
///   needed, no risk of address / admin‑region matches).  All POI categories
///   are included via ``.includingAll``; administrative divisions that
///   somehow slip through are caught by ``isAdministrativeRegion(item:)``.
///
/// - **Text search** (user types in search bar → 300 ms debounce):
///   Uses ``MKLocalSearch`` with the query as ``naturalLanguageQuery``,
///   ``resultTypes: [.pointOfInterest, .address]``, scoped to the current
///   map region.
///
/// # Task management
///
/// Two independent task slots prevent text search and camera‑triggered
/// search from cancelling each other:
/// - ``searchTask`` — text search / clear.
/// - ``nearbySearchTask`` — camera‑triggered POI search & current‑location refresh.
struct LocationPickerView: View {
    @Binding var selectedName: String?
    @Binding var selectedLatitude: Double?
    @Binding var selectedLongitude: Double?
    @Binding var selectedPlacemark: CLPlacemark?

    @Environment(\.dismiss) private var dismiss

    // ── Camera ───────────────────────────────────────────────────
    /// Single source of truth for ALL coordinate‑based queries.
    /// Only written by camera callbacks and ``fetchCurrentLocation()``.
    @State private var cameraPosition: MapCameraPosition
    @State private var mapCenter: CLLocationCoordinate2D

    // ── Places ───────────────────────────────────────────────────
    /// POIs returned from ``searchNearbyPOIs(center:)``.
    @State private var nearbyPlaces: [NearbyPlace] = []
    /// Results from ``performSearch(query:)``.
    @State private var searchResults: [NearbyPlace] = []
    /// Currently highlighted place (set on tap, cleared on map drag).
    @State private var selectedPlace: NearbyPlace?

    // ── Search state ─────────────────────────────────────────────
    @State private var searchQuery = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var nearbySearchTask: Task<Void, Never>?
    @State private var isSearching = false

    /// `true` while a programmatic camera animation is in progress
    /// (triggered by tapping a POI or using 当前位置). During this window the
    /// ``onMapCameraChange(frequency: .continuous)`` handler skips the nearby
    /// search — the map is moving because the user *selected* something,
    /// not because they dragged.
    @State private var isAnimatingToPlace = false
    @State private var isFetchingCurrentLocation = false

    // ── Bottom sheet ─────────────────────────────────────────────
    @State private var sheetDetent: SheetDetent = .small
    @State private var sheetDragOffset: CGFloat = 0

    // ── Convenience ──────────────────────────────────────────────
    private let locationService = LocationService.shared

    private var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The list currently shown in the bottom panel.
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
                    // Revert to nearby places
                    await MainActor.run { searchResults = [] }
                } else {
                    await performSearch(query: newValue)
                }
            }
        }
        .onAppear {
            print("[LocationPicker] onAppear — starting initial POI search at center")
            nearbySearchTask?.cancel()
            nearbySearchTask = Task {
                print("[LocationPicker] onAppear Task — searching near (\(mapCenter.latitude), \(mapCenter.longitude))")
                await searchNearbyPOIs(center: mapCenter)
            }
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
            let newCenter = context.region.center
            mapCenter = newCenter
            print("[LocationPicker] camera continuous — center=(\(newCenter.latitude), \(newCenter.longitude)) isAnimating=\(isAnimatingToPlace)")

            // ── Skip search during programmatic animation ─────
            if isAnimatingToPlace { return }

            // ── Debounced POI search on user drag ─────────────
            nearbySearchTask?.cancel()
            nearbySearchTask = Task { [center = newCenter] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else {
                    print("[LocationPicker] camera debounce — cancelled")
                    return
                }
                let shouldSearch = await MainActor.run { !isAnimatingToPlace }
                guard shouldSearch else {
                    print("[LocationPicker] camera debounce — suppressed (isAnimating)")
                    return
                }
                print("[LocationPicker] camera debounce — starting POI search")
                await searchNearbyPOIs(center: center)
            }
        }
        .onMapCameraChange(frequency: .onEnd) { _ in
            if !isAnimatingToPlace {
                selectedPlace = nil
            }
            print("[LocationPicker] camera onEnd — selectedPlace cleared=\(!isAnimatingToPlace)")
        }
        .overlay(alignment: .center) {
            // Fixed centre pin — visual only, never blocks map gestures
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
    /// - Drag the **handle** ↕ to toggle between 35 % and 90 % height.
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .zIndex(50)
    }

    /// Drag gesture on the capsule handle — avoids conflicts with both
    /// the ``ScrollView`` and the ``Map`` gestures underneath.
    ///
    /// Snap logic (Apple Maps‑style):
    /// - Velocity > 300 pt/s downward → collapse to ``.small``.
    /// - Velocity < -300 pt/s upward → expand to ``.large``.
    /// - Otherwise → snap to nearest detent.
    private var sheetDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                sheetDragOffset = value.translation.height
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height
                sheetDragOffset = 0

                let allDetents = SheetDetent.allCases.sorted { $0.rawValue < $1.rawValue }

                let target: SheetDetent
                if velocity > 300 {
                    target = .small
                } else if velocity < -300 {
                    target = .large
                } else {
                    let currentFraction = sheetDetent.rawValue
                    let offsetFraction = sheetDragOffset / UIScreen.main.bounds.height
                    let proposed = currentFraction - offsetFraction
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
    /// After the animation completes, triggers a nearby POI search for the
    /// selected location so the bottom sheet is always up to date.
    private func selectPlace(_ place: NearbyPlace) {
        selectedPlace = place
        isAnimatingToPlace = true

        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: place.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }

        // Wait for animation + settle, then refresh nearby places
        // and release the animation lock.
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            await MainActor.run {
                isAnimatingToPlace = false
            }
            // 🔁 Refresh nearby places for the selected location
            // (camera .continuous won't fire after the animation stops,
            //  so we must trigger the search explicitly.)
            print("[LocationPicker] selectPlace — animation done, refreshing nearby for selected location")
            await searchNearbyPOIs(center: place.coordinate)
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
    /// nearby POIs immediately.
    ///
    /// Flow:
    /// 1. ``LocationService.requestLocation()``
    /// 2. Update ``mapCenter`` directly (single source of truth).
    /// 3. Set ``isAnimatingToPlace`` to block .continuous search.
    /// 4. Move ``cameraPosition``.
    /// 5. Call ``searchNearbyPOIs(center:)` — not debounced.
    /// 6. Reset ``isAnimatingToPlace`` when search completes.
    private func fetchCurrentLocation() {
        isFetchingCurrentLocation = true
        Task {
            let result = await locationService.requestLocation()
            await MainActor.run {
                guard let lat = result.latitude, let lng = result.longitude else {
                    print("[LocationPicker] fetchCurrentLocation — failed (no location)")
                    isFetchingCurrentLocation = false
                    return
                }

                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                print("[LocationPicker] fetchCurrentLocation — got (\(lat), \(lng))")

                // ── Single source of truth ────────────────────────
                mapCenter = coord
                isAnimatingToPlace = true

                cameraPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))

                // ── Immediate POI search (not debounced) ──────────
                nearbySearchTask?.cancel()
                nearbySearchTask = Task {
                    print("[LocationPicker] fetchCurrentLocation — starting POI search")
                    await searchNearbyPOIs(center: coord)
                    await MainActor.run { isAnimatingToPlace = false }
                }

                selectedPlace = nil
                isFetchingCurrentLocation = false
            }
        }
    }

    // MARK: - Nearby POI Search (iOS 26 MapKit POI Search)

    /// **Only** entry point for nearby‑place search.
    ///
    /// Uses Apple's official POI‑only search API
    /// ``MKLocalPointsOfInterestRequest`` (iOS 16+) — this takes a centre
    /// coordinate and radius, does NOT need a ``naturalLanguageQuery``,
    /// and returns only point‑of‑interest results (no address / admin‑region
    /// matches).
    ///
    /// All POI categories are included via ``.includingAll`` filter.
    /// Administrative divisions that somehow slip through are caught by
    /// ``isAdministrativeRegion(item:)``.
    ///
    /// - Parameter center: **Must** be ``mapCenter`` — guaranteed by caller.
    private func searchNearbyPOIs(center: CLLocationCoordinate2D) async {
        let radius = searchRadius(from: MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        print("""
        ┌─ [LocationPicker] Nearby POI Search ─────────────────────
        │ Camera Center:  \(center.latitude), \(center.longitude)
        │ Search Radius:  \(Int(radius))m
        │ API:            MKLocalPointsOfInterestRequest
        │ Filter:         .includingAll
        └──────────────────────────────────────────────────────────
        """)

        isSearching = true
        defer {
            isSearching = false
            print("[LocationPicker] Nearby POI Search — isSearching=false")
        }

        // ── 1. Build the POI‑only request ─────────────────────────
        // MKLocalPointsOfInterestRequest is the iOS 16+ official API
        // for "find POIs near this location".  It requires NO query
        // string and returns ONLY .pointOfInterest results — address
        // / admin‑region matches are impossible.
        let poiRequest = MKLocalPointsOfInterestRequest(
            center: center,
            radius: radius
        )
        poiRequest.pointOfInterestFilter = nearbyPOIFilter

        let search = MKLocalSearch(request: poiRequest)

        // ── 2. Execute ───────────────────────────────────────────
        let response: MKLocalSearch.Response
        do {
            response = try await search.start()
            print("[LocationPicker] ✅ MKLocalSearch.start() succeeded")
        } catch {
            print("[LocationPicker] ❌ Nearby Search Error: \(error.localizedDescription)")
            return
        }

        guard !Task.isCancelled else {
            print("[LocationPicker] Nearby POI Search — cancelled after response")
            return
        }

        // ── 3. Debug: log every raw result ───────────────────────
        print("[LocationPicker] Apple Returned: \(response.mapItems.count) items")
        for (i, item) in response.mapItems.enumerated() {
            let cat = item.pointOfInterestCategory?.rawValue ?? -1
            print("  [\(i)] name=\(item.name ?? "nil") category=\(cat) title=\(item.placemark.title ?? "nil")")
        }

        // ── 4. Filter out administrative regions ─────────────────
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)

        let beforeFilter = response.mapItems.count

        let places: [NearbyPlace] = response.mapItems
            .compactMap { item in
                guard let name = item.name else {
                    print("[LocationPicker]   filter: dropped (nil name)")
                    return nil
                }
                if isAdministrativeRegion(item: item) {
                    print("[LocationPicker]   filter: dropped admin region — \(name)")
                    return nil
                }
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

        print("[LocationPicker] Filter Before: \(beforeFilter)  After: \(places.count)")

        // ── 5. Update UI on MainActor ────────────────────────────
        await MainActor.run {
            guard !Task.isCancelled else {
                print("[LocationPicker] Nearby POI Search — cancelled before UI update")
                return
            }
            nearbyPlaces = places
            print("[LocationPicker] ✅ Nearby Updated: \(places.count) places in nearbyPlaces")
        }
    }

    // MARK: - Text Search (MKLocalSearch)

    /// Performs a **keyword** search using the user's typed query.
    ///
    /// Unlike ``searchNearbyPOIs(center:)`` this uses ``naturalLanguageQuery``
    /// and includes ``.address`` in result types so the user can find
    /// places by name (e.g. "逸景雅居", "万达", "西安交大").
    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            await MainActor.run { searchResults = [] }
            return
        }

        print("[LocationPicker] Text Search — query=\"\(trimmed)\" near (\(mapCenter.latitude), \(mapCenter.longitude))")
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
        let response: MKLocalSearch.Response
        do {
            response = try await search.start()
        } catch {
            print("[LocationPicker] ❌ Text Search Error: \(error.localizedDescription)")
            return
        }
        guard !Task.isCancelled else { return }

        print("[LocationPicker] Text Search — Apple returned \(response.mapItems.count) items")

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
            print("[LocationPicker] Text Search — Updated \(places.count) search results")
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
