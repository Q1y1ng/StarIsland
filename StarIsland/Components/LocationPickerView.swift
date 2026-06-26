import SwiftUI
import MapKit

// MARK: - Location Picker View

/// A bottom sheet that lets the user pick a location via map tap, search,
/// or current location.  Uses the iOS 17+ MapKit API (no UIKit).
///
/// ```
/// ┌──────────────────────────────┐
/// │  🔍 搜索地点                  │
/// │                              │
│ │         🗺️ Map               │
│ │    (tap to select POI)       │
│ │                              │
│ │  📍 当前位置                   │
│ │  ┌──────────────────────┐    │
│ │  │      确定              │    │
│ │  └──────────────────────┘    │
│ └──────────────────────────────┘
/// ```
struct LocationPickerView: View {
    @Binding var selectedName: String?
    @Binding var selectedLatitude: Double?
    @Binding var selectedLongitude: Double?

    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var selectedMapItem: MKMapItem?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isFetchingCurrentLocation = false
    @State private var mapSelection: MKMapItem?
    @State private var searchTask: Task<Void, Never>?

    /// Identifiable wrapper for MKMapItem (not Hashable)
    private struct MapItemWrapper: Identifiable {
        let id = UUID()
        let item: MKMapItem
    }

    private var searchItemWrappers: [MapItemWrapper] {
        searchResults.map { MapItemWrapper(item: $0) }
    }

    private let locationService = LocationService.shared

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Search bar ───────────────────────────────────────
                searchBar
                    .padding(.horizontal, AppTheme.spacing.xlarge)
                    .padding(.vertical, AppTheme.spacing.medium)

                // ── Map with tap-to-place ────────────────────────────
                MapReader { reader in
                    Map(position: $cameraPosition, selection: $mapSelection) {
                        // Highlight search results
                        ForEach(searchItemWrappers) { wrapper in
                            Marker(item: wrapper.item)
                        }

                        // Selected location annotation
                        if let item = selectedMapItem,
                           !searchResults.contains(where: { $0.placemark.coordinate.latitude == item.placemark.coordinate.latitude }) {
                            Marker(item: item)
                        }
                    }
                    .mapStyle(.standard)
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    .onTapGesture { screenPoint in
                        if let coordinate = reader.convert(screenPoint, from: .local) {
                            reverseGeocode(coordinate: coordinate)
                        }
                    }
                }

                // ── Bottom actions ───────────────────────────────────
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
        .onChange(of: mapSelection) { _, newValue in
            if let item = newValue {
                selectedMapItem = item
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
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacing.small)
            }
            .disabled(isFetchingCurrentLocation)

            // Show search results below current location
            if !searchResults.isEmpty {
                searchResultsList
            }

            // Selected location info + confirm
            if let item = selectedMapItem {
                VStack(spacing: AppTheme.spacing.small) {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.blue)
                        Text(item.name ?? "未知地点")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        if let area = item.placemark.subLocality ?? item.placemark.locality {
                            Text(area)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, AppTheme.spacing.xlarge)

                    Button {
                        confirmSelection(item)
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
                    .padding(.horizontal, AppTheme.spacing.xlarge)
                }
                .padding(.bottom, AppTheme.spacing.medium)
            }
        }
        .background(Color(.systemBackground))
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
                                Text(item.name ?? "")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                if let locality = item.placemark.locality {
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

    // MARK: - Actions

    private func fetchCurrentLocation() {
        isFetchingCurrentLocation = true
        Task {
            let result = await locationService.requestLocation()
            await MainActor.run {
                if let lat = result.latitude, let lng = result.longitude {
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    cameraPosition = .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                    reverseGeocode(coordinate: coordinate)
                }
                isFetchingCurrentLocation = false
            }
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        selectedMapItem = item
        mapSelection = item
        cameraPosition = .region(MKCoordinateRegion(
            center: item.placemark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        searchQuery = ""
        searchResults = []
    }

    private func reverseGeocode(coordinate: CLLocationCoordinate2D) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard let placemark = placemarks?.first else { return }

            let name: String = {
                // Street-first priority
                if let subLocality = placemark.subLocality,
                   let thoroughfare = placemark.thoroughfare {
                    return "\(thoroughfare) · \(subLocality)"
                }
                if let thoroughfare = placemark.thoroughfare {
                    return thoroughfare
                }
                if let locality = placemark.locality {
                    return locality
                }
                return placemark.name ?? String(format: "%.4f, %.4f",
                                               coordinate.latitude, coordinate.longitude)
            }()

            let placemarkCoord = placemark.location?.coordinate ?? coordinate
            let item = MKMapItem(placemark: MKPlacemark(coordinate: placemarkCoord))
            item.name = name

            DispatchQueue.main.async {
                selectedMapItem = item
                mapSelection = item
            }
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

        // Use current visible region or default to Xi'an
        if case .region(let region) = cameraPosition {
            request.region = region
        } else {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 34.3416, longitude: 108.9398),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            await MainActor.run {
                searchResults = response.mapItems
                if let first = response.mapItems.first, !searchQuery.isEmpty {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: first.placemark.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
        } catch {
            print("[LocationPicker] search error: \(error.localizedDescription)")
        }
    }

    private func confirmSelection(_ item: MKMapItem) {
        let placemark = item.placemark

        // Build name with street-first priority
        let name: String = {
            // Street + sub-locality (e.g. "长安中路 · 小寨")
            if let subLocality = placemark.subLocality,
               let thoroughfare = placemark.thoroughfare {
                return "\(thoroughfare) · \(subLocality)"
            }
            // Street only
            if let thoroughfare = placemark.thoroughfare {
                return thoroughfare
            }
            // POI name (last resort)
            if let n = placemark.name {
                return n
            }
            // Administrative area + city
            if let subAdmin = placemark.subAdministrativeArea,
               let locality = placemark.locality {
                return "\(subAdmin) · \(locality)"
            }
            // City
            if let locality = placemark.locality {
                return locality
            }
            // Coordinates
            return String(format: "%.4f, %.4f",
                         placemark.coordinate.latitude,
                         placemark.coordinate.longitude)
        }()

        selectedName = name
        selectedLatitude = placemark.coordinate.latitude
        selectedLongitude = placemark.coordinate.longitude
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    LocationPickerView(
        selectedName: .constant(nil),
        selectedLatitude: .constant(nil),
        selectedLongitude: .constant(nil)
    )
}
