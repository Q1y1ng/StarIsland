import SwiftUI
import SwiftData
import MapKit

// MARK: - Footprint View

/// Life trajectory — a chronologically ordered polyline connecting
/// every recorded location from the last 30 days.
///
/// ```
/// ┌──────────────────────────────────┐
/// │  👣 足迹                         │
/// │  最近 30 天 · 18 个坐标点         │
/// │                                  │
/// │  ┌───── Map ──────────────────┐  │
/// │  │    ╭───╮                   │  │
/// │  │   ╱     ╲──╮              │  │
/// │  │  ╱         ╲───╮         │  │
/// │  │ ╱              ╲───╮    │  │
/// │  └──────────────────────────┘  │
/// └──────────────────────────────────┘
/// ```
///
/// Colours are `Color.primary.opacity(...)` — never custom.
struct FootprintView: View {
    @Environment(\.modelContext) private var context

    @State private var coordinates: [CLLocationCoordinate2D] = []
    @State private var pointCount: Int = 0
    @State private var region: MKCoordinateRegion?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────
            headerView
                .padding(.horizontal, AppTheme.spacing.xxxlarge)
                .padding(.top, AppTheme.spacing.xxxlarge)
                .padding(.bottom, AppTheme.spacing.medium)

            // ── Map ────────────────────────────────────────────────
            if coordinates.count >= 2, let region {
                Map(
                    position: .constant(.region(region))
                ) {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.primary.opacity(0.35), lineWidth: 2)

                    // Start marker
                    if let first = coordinates.first {
                        Annotation("起点", coordinate: first, anchor: .bottom) {
                            Circle()
                                .fill(.primary)
                                .frame(width: 8, height: 8)
                        }
                    }

                    // End marker
                    if let last = coordinates.last, coordinates.count > 1 {
                        Annotation("终点", coordinate: last, anchor: .bottom) {
                            Circle()
                                .fill(.primary)
                                .frame(width: 10, height: 10)
                        }
                    }
                }
                .mapStyle(.standard)
                .allowsHitTesting(true)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius.large, style: .continuous))
                .padding(.horizontal, AppTheme.spacing.xxxlarge)
            } else {
                emptyState
            }

            Spacer(minLength: AppTheme.spacing.huge)
        }
        .background(Color(.systemBackground))
        .navigationTitle("足迹")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadData)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xxsmall) {
            Text("👣")
                .font(.system(size: 36))
                .padding(.bottom, AppTheme.spacing.xxsmall)

            Text("足迹")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text("最近 30 天 · \(pointCount) 个坐标点")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppTheme.spacing.xlarge) {
            Spacer()
            Text("暂无足迹数据")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("记录包含位置的信息将显示在这里")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func loadData() {
        let descriptor = FetchDescriptor<Record>(
            predicate: #Predicate { !$0.isTrashed }
        )
        guard let records = try? context.fetch(descriptor) else { return }

        let coords = MapService.footprintCoordinates(from: records)
        coordinates = coords
        pointCount = coords.count

        if coords.count >= 2 {
            calculateRegion(for: coords)
        }
    }

    private func calculateRegion(for coords: [CLLocationCoordinate2D]) {
        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLng = coords[0].longitude, maxLng = coords[0].longitude

        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude)
            maxLng = max(maxLng, c.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5 + 0.01,
            longitudeDelta: (maxLng - minLng) * 1.5 + 0.01
        )
        region = MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FootprintView()
            .modelContainer(for: Record.self, inMemory: true)
    }
}
