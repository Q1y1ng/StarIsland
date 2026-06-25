import SwiftUI

// MARK: - App Tab

/// The six tabs of StarIsland.
enum AppTab: String, CaseIterable {
    case timeline
    case archive
    case map
    case search
    case stats
    case settings

    var label: String {
        switch self {
        case .timeline: return "时间线"
        case .archive:  return "回顾"
        case .map:      return "地图"
        case .search:   return "搜索"
        case .stats:    return "统计"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .timeline: return "clock.fill"
        case .archive:  return "square.grid.3x3.fill"
        case .map:      return "map.fill"
        case .search:   return "magnifyingglass"
        case .stats:    return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Content View

/// Root view managing the `TabView` and cross‑tab navigation state.
///
/// ## Cross‑tab navigation
///
/// - ``ArchiveView`` → ``TimelineView``: scroll to a specific date.
/// - ``SearchView`` → ``MapView``: focus on a matching location.
struct ContentView: View {
    @State private var selectedTab: AppTab = .timeline
    @State private var scrollToDate: Date? = nil
    @State private var focusLocation: String? = nil

    private let locationService = LocationService()

    var body: some View {
        TabView(selection: $selectedTab) {
            // ── Timeline ──────────────────────────────────────────
            NavigationStack {
                TimelineView(
                    scrollToDate: $scrollToDate,
                    selectedTab: $selectedTab
                )
            }
            .tabItem {
                Label(AppTab.timeline.label, systemImage: AppTab.timeline.icon)
            }
            .tag(AppTab.timeline)

            // ── Archive ───────────────────────────────────────────
            NavigationStack {
                ArchiveView(
                    selectedTab: $selectedTab,
                    scrollToDate: $scrollToDate
                )
            }
            .tabItem {
                Label(AppTab.archive.label, systemImage: AppTab.archive.icon)
            }
            .tag(AppTab.archive)

            // ── Map ───────────────────────────────────────────────
            NavigationStack {
                MapView(
                    selectedTab: $selectedTab,
                    focusLocation: $focusLocation
                )
            }
            .tabItem {
                Label(AppTab.map.label, systemImage: AppTab.map.icon)
            }
            .tag(AppTab.map)

            // ── Search ────────────────────────────────────────────
            NavigationStack {
                SearchView(
                    selectedTab: $selectedTab,
                    focusLocation: $focusLocation
                )
            }
            .tabItem {
                Label(AppTab.search.label, systemImage: AppTab.search.icon)
            }
            .tag(AppTab.search)

            // ── Stats ─────────────────────────────────────────────
            NavigationStack {
                StatsView()
            }
            .tabItem {
                Label(AppTab.stats.label, systemImage: AppTab.stats.icon)
            }
            .tag(AppTab.stats)

            // ── Settings ───────────────────────────────────────────
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(AppTab.settings.label, systemImage: AppTab.settings.icon)
            }
            .tag(AppTab.settings)
        }
        .onAppear {
            locationService.requestPermission()
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: Record.self, inMemory: true)
}
