import SwiftUI
import SwiftData
import MapKit

// MARK: - Map View

/// Memory Map — pins every location where the user has recorded a time slice.
///
/// ```
/// ┌──────────────────────────────────┐
/// │  记忆地图                         │
/// │  共 37 个地点 · 最常: 学校         │
/// │                                  │
/// │  [今天 | 最近7天 | 最近30天 | 全部] │
/// │                                  │
/// │  ┌───── Map ──────────────────┐  │
/// │  │     📍                      │  │
/// │  │        📍                   │  │
/// │  │                    📍       │  │
/// │  │  📍                         │  │
/// │  └─────────────────────────────┘  │
/// └──────────────────────────────────┘
/// ```
///
/// ## Cross‑tab linkage
/// When ``SearchView`` finds a location match it sets `focusLocation`
/// and `selectedTab` so the map zooms to that pin automatically.
struct MapView: View {
    @Binding var selectedTab: AppTab
    @Binding var focusLocation: String?

    @Environment(\.modelContext) private var context

    @State private var locations: [MemoryLocation] = []
    @State private var allRecords: [Record] = []
    @State private var timeFilter: TimeFilter = .all
    @State private var selectedLocation: MemoryLocation?
    @State private var showingDetail = false
    @State private var showingFootprint = false
    @State private var showFootprintPage = false

    @State private var position: MapCameraPosition = .automatic

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────
            headerView
                .padding(.horizontal, AppTheme.spacing.xxxlarge)
                .padding(.top, AppTheme.spacing.xlarge)
                .padding(.bottom, AppTheme.spacing.medium)

            // ── Time filter ───────────────────────────────────────
            Picker("时间", selection: $timeFilter) {
                ForEach(TimeFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.spacing.xxxlarge)
            .padding(.bottom, AppTheme.spacing.medium)

            // ── Map ────────────────────────────────────────────────
            Map(position: $position, selection: $selectedLocation) {
                ForEach(locations) { location in
                    Annotation(location.name, coordinate: location.coordinate, anchor: .bottom) {
                        pinView(for: location)
                    }
                    .tag(location)
                }

                // Footprint polyline when activated
                if showingFootprint {
                    let coords = MapService.footprintCoordinates(from: allRecords)
                    if coords.count >= 2 {
                        MapPolyline(coordinates: coords)
                            .stroke(.primary.opacity(0.35), lineWidth: 1.5)
                    }
                }
            }
            .mapStyle(.standard)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius.large, style: .continuous))
            .padding(.horizontal, AppTheme.spacing.xxxlarge)
            .padding(.bottom, AppTheme.spacing.medium)
            .onChange(of: selectedLocation) { _, newLoc in
                if newLoc != nil { showingDetail = true }
            }
            .onChange(of: timeFilter) { _, _ in reloadLocations() }

            // ── Footprint toggle ──────────────────────────────────
            Button {
                withAnimation(.interactiveSpring) {
                    showingFootprint.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.spacing.small) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .foregroundStyle(showingFootprint ? .primary : .tertiary)
                    Text("足迹模式")
                        .font(.caption)
                        .foregroundStyle(showingFootprint ? .primary : .tertiary)
                }
                .padding(.horizontal, AppTheme.spacing.large)
                .padding(.vertical, AppTheme.spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius.medium)
                        .fill(Color(.systemGray6))
                )
            }
            .padding(.bottom, AppTheme.spacing.medium)
        }
        .background(Color(.systemBackground))
        .navigationTitle("地图")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFootprintPage = true
                } label: {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                }
            }
        }
        .navigationDestination(isPresented: $showFootprintPage) {
            FootprintView()
        }
        .onAppear(perform: loadData)
        .onChange(of: focusLocation) { _, newValue in
            guard let name = newValue else { return }
            focusOnLocation(name)
            focusLocation = nil  // consume
        }
        .sheet(isPresented: $showingDetail) {
            if let location = selectedLocation {
                LocationDetailView(location: location)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xxsmall) {
            Text("🗺️")
                .font(.system(size: 36))
                .padding(.bottom, AppTheme.spacing.xxsmall)

            Text("记忆地图")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            HStack(spacing: AppTheme.spacing.medium) {
                Text("共 \(locations.count) 个地点")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if locations.count >= 2 {
                    dotSeparator
                    let most = MapService.topLocation(locations)?.name ?? ""
                    Text("最常: \(most)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var dotSeparator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
    }

    // MARK: - Pin

    private func pinView(for location: MemoryLocation) -> some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

            Text("📍")
                .font(.system(size: 14))
        }
    }

    // MARK: - Focus

    private func focusOnLocation(_ name: String) {
        guard let location = locations.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else { return }

        position = .region(MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
        selectedLocation = location
        showingDetail = true
    }

    // MARK: - Data

    private func loadData() {
        let descriptor = FetchDescriptor<Record>(
            predicate: #Predicate { !$0.isTrashed }
        )
        allRecords = (try? context.fetch(descriptor)) ?? []
        reloadLocations()
    }

    private func reloadLocations() {
        locations = MapService.aggregateLocations(from: allRecords, timeFilter: timeFilter)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MapView(
            selectedTab: .constant(.map),
            focusLocation: .constant(nil)
        )
        .modelContainer(for: Record.self, inMemory: true)
    }
}
