import SwiftUI
import MapKit
import CoreLocation

// MARK: - Location Picker View

/// A bottom sheet that lets the user pick a location via map drag (fixed pin),
/// search, or current location.  Uses the iOS 17+ MapKit API (no UIKit).
///
/// T4.7 — redesigned with a fixed center pin:
/// ```
/// ┌──────────────────────────────┐
/// │  🔍 搜索地点                  │
/// │                              │
/// │         🗺️ Map              │
/// │         📍 (fixed pin)       │
/// │   drag map → pin stays still │
/// │                              │
/// │  📍 当前位置                   │
/// │  长安中路89号 · 小寨 · 雁塔区   │
/// │                              │
/// │  [         确定              ]│
/// └──────────────────────────────┘
/// ```
struct LocationPickerView: View {
    @Binding var selectedName: String?
    @Binding var selectedLatitude: Double?
    @Binding var selectedLongitude: Double?
    @Binding var selectedPlacemark: CLPlacemark?

    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var cameraPosition: MapCameraPosition
    @State private var currentPlacemark: CLPlacemark?
    @State private var isFetchingCurrentLocation = false
    @State private var searchTask: Task<Void, Never>?
    @State private var geocodeTask: Task<Void, Never>?

    /// Identifiable wrapper for MKMapItem (not Hashable)
    private struct MapItemWrapper: Identifiable {
        let id = UUID()
        let item: MKMapItem
    }

    private var searchItemWrappers: [MapItemWrapper] {
        searchResults.map { MapItemWrapper(item: $0) }
    }

    private let locationService = LocationService.shared

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
            VStack(spacing: 0) {
                // ── Search bar ───────────────────────────────────────
                searchBar
                    .padding(.horizontal, AppTheme.spacing.xlarge)
                    .padding(.vertical, AppTheme.spacing.medium)

                // ── Map with fixed pin overlay ───────────────────────
                ZStack {
                    Map(position: $cameraPosition) {
                        // Search result markers
                        ForEach(searchItemWrappers) { wrapper in
                            Marker(item: wrapper.item)
                        }
                    }
                    .mapStyle(.standard)
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    .onMapCameraChange { context in
                        let center = context.region.center
                        geocodeTask?.cancel()
                        geocodeTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            await reverseGeocode(coordinate: center)
                        }
                    }

                    // Fixed center pin — always stays at map center
                    Image(systemName: "mappin")
                        .font(.title)
                        .foregroundStyle(.blue)
                        .offset(y: -16) // pin tip aligns with center
                }

                // ── Bottom bar ───────────────────────────────────────
                bottomBar
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
                await performSearch(query: newValue)
            }
        }
        .onAppear {
            // If we have an initial location but no placemark yet,
            // reverse geocode the initial coordinate
            if currentPlacemark == nil,
               let lat = selectedLatitude,
               let lng = selectedLongitude {
                Task {
                    await reverseGeocode(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                }
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

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: AppTheme.spacing.medium) {
            Divider()

            // Current location button
            currentLocationButton
                .padding(.horizontal, AppTheme.spacing.xlarge)

            // Location details (real-time from map center)
            if let placemark = currentPlacemark {
                locationDetailView(placemark)
                    .padding(.horizontal, AppTheme.spacing.xlarge)
            }

            // Search results (horizontal scroll)
            if !searchResults.isEmpty {
                searchResultsList
            }

            // Confirm button
            if currentPlacemark != nil {
                confirmButton
                    .padding(.horizontal, AppTheme.spacing.xlarge)
                    .padding(.bottom, AppTheme.spacing.medium)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Current Location Button

    private var currentLocationButton: some View {
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing.small)
        }
        .disabled(isFetchingCurrentLocation)
    }

    // MARK: - Location Detail View

    @ViewBuilder
    private func locationDetailView(_ pm: CLPlacemark) -> some View {
        VStack(spacing: AppTheme.spacing.xsmall) {
            // Header
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.subheadline)
                Text("当前位置")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            // Composed address string (e.g. "长安中路89号 · 小寨 · 雁塔区 · 西安市")
            let address = buildAddressString(pm)
            if !address.isEmpty {
                HStack {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            // Hierarchy chips (e.g. "门牌 · 街道 · 行政区 · 城市")
            let chips = buildHierarchyChips(pm)
            if !chips.isEmpty {
                HStack(spacing: AppTheme.spacing.small) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        Text(chip.label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Search Results List

    private var searchResultsList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacing.medium) {
                ForEach(searchItemWrappers) { wrapper in
                    Button {
                        selectSearchResult(wrapper.item)
                    } label: {
                        HStack(spacing: AppTheme.spacing.small) {
                            Image(systemName: "mappin")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wrapper.item.name ?? "")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                if let locality = wrapper.item.placemark.locality {
                                    Text(locality)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.spacing.medium)
                        .padding(.vertical, AppTheme.spacing.small)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, AppTheme.spacing.xlarge)
        }
        .frame(height: 50)
    }

    // MARK: - Confirm Button

    private var confirmButton: some View {
        Button {
            confirmSelection()
        } label: {
            Text("确定")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Actions

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
                    // onMapCameraChange will trigger reverse geocode
                }
                isFetchingCurrentLocation = false
            }
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        cameraPosition = .region(MKCoordinateRegion(
            center: item.placemark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        searchQuery = ""
        searchResults = []
        // onMapCameraChange will trigger reverse geocode for the new center
    }

    private func reverseGeocode(coordinate: CLLocationCoordinate2D) async {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        let placemarks: [CLPlacemark] = await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { marks, _ in
                continuation.resume(returning: marks ?? [])
            }
        }

        guard let placemark = placemarks.first, !Task.isCancelled else { return }
        await MainActor.run {
            currentPlacemark = placemark
        }
    }

    private func performSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]

        let cameraRegion: MKCoordinateRegion
        switch cameraPosition {
        case .region(let region):
            cameraRegion = region
        default:
            cameraRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 34.3416, longitude: 108.9398),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        request.region = cameraRegion

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            await MainActor.run {
                searchResults = response.mapItems
            }
        } catch {
            print("[LocationPicker] search error: \(error.localizedDescription)")
        }
    }

    private func confirmSelection() {
        guard let placemark = currentPlacemark else { return }

        let name = buildSelectedName(from: placemark)
        let coord = placemark.location?.coordinate
            ?? extractCoordinate(from: cameraPosition)

        selectedName = name
        selectedLatitude = coord.latitude
        selectedLongitude = coord.longitude
        selectedPlacemark = placemark
        dismiss()
    }

    // MARK: - Helpers

    /// Build display name with street-first priority (same as LocationService).
    private func buildSelectedName(from pm: CLPlacemark) -> String {
        // 1. Door number (thoroughfare + subThoroughfare)
        if let thr = pm.thoroughfare, let sub = pm.subThoroughfare {
            return "\(thr) \(sub)"
        }
        // 2. Street (thoroughfare only)
        if let thr = pm.thoroughfare {
            return thr
        }
        // 3. Neighborhood / 商圈 (subLocality)
        if let sub = pm.subLocality {
            return sub
        }
        // 4. District + city (subAdministrativeArea + locality)
        if let sub = pm.subAdministrativeArea, let loc = pm.locality {
            return "\(sub) · \(loc)"
        }
        // 5. City (locality only)
        if let loc = pm.locality {
            return loc
        }
        // 6. POI / place name (last resort — avoid shop names)
        if let name = pm.name {
            return name
        }
        // 7. Coordinates
        let coord = pm.location?.coordinate
            ?? extractCoordinate(from: cameraPosition)
        return String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
    }

    /// Build a readable address string for the detail view.
    private func buildAddressString(_ pm: CLPlacemark) -> String {
        var parts: [String] = []
        if let thr = pm.thoroughfare, let sub = pm.subThoroughfare {
            parts.append("\(thr) \(sub)")
        } else if let thr = pm.thoroughfare {
            parts.append(thr)
        }
        if let sub = pm.subLocality {
            parts.append(sub)
        }
        if let sub = pm.subAdministrativeArea {
            parts.append(sub)
        }
        if let loc = pm.locality {
            parts.append(loc)
        }
        return parts.isEmpty ? (pm.name ?? "未知地点") : parts.joined(separator: " · ")
    }

    /// Build hierarchy chips for display (e.g. 门牌/街道/行政区/城市).
    private func buildHierarchyChips(_ pm: CLPlacemark) -> [(label: String, value: String)] {
        var chips: [(String, String)] = []
        if let thr = pm.thoroughfare, let sub = pm.subThoroughfare {
            chips.append(("门牌", "\(thr) \(sub)"))
        } else if let thr = pm.thoroughfare {
            chips.append(("街道", thr))
        }
        if let sub = pm.subLocality {
            chips.append(("商圈", sub))
        }
        if let sub = pm.subAdministrativeArea {
            chips.append(("区", sub))
        }
        if let loc = pm.locality {
            chips.append(("市", loc))
        }
        return chips
    }

    /// Extract center coordinate from MapCameraPosition.
    private func extractCoordinate(from position: MapCameraPosition) -> CLLocationCoordinate2D {
        switch position {
        case .region(let region):
            return region.center
        default:
            return CLLocationCoordinate2D(latitude: 34.3416, longitude: 108.9398)
        }
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
