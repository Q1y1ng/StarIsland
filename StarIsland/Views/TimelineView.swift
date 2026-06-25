import SwiftUI
import SwiftData

// MARK: - Timeline View

/// Primary screen — displays records grouped by day.
///
/// Uses a custom `ScrollView` + `LazyVStack` layout (no `List`).
///
/// ## Phase 2.5 additions
/// - ``HomeHeaderView`` replacing the navigation title (Apple Journal style)
/// - Soft‑delete filtering (`isTrashed == false`)
/// - Insert animation on Quick Capture
/// - **Hero transition** for images (matched‑geometry effect → full‑screen viewer)
/// - Search button in the toolbar
///
/// ## Phase 3 additions
/// - ``ScrollViewReader`` for cross‑tab scroll‑to‑date (triggered by ``ArchiveView``)
/// - Search button now switches to the **Search** tab instead of pushing
struct TimelineView: View {
    @Binding var scrollToDate: Date?
    @Binding var selectedTab: AppTab

    @Query(
        filter: #Predicate<Record> { !$0.isTrashed },
        sort: \Record.timestamp, order: .reverse
    )
    private var records: [Record]

    @State private var showingAddRecord = false

    // Insert animation
    @State private var previousCount = 0
    @State private var newRecordID: UUID?

    // Hero transition
    @Namespace private var heroNamespace
    @State private var heroPhoto: HeroPhotoState?

    // Scroll highlight
    @State private var highlightedDate: Date?

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── Main scroll content ─────────────────────────────
            Group {
                if records.isEmpty {
                    EmptyStateView()
                } else {
                    timelineList
                }
            }

            // ── Hero overlay ────────────────────────────────────
            if let hero = heroPhoto {
                heroOverlay(hero)
                    .ignoresSafeArea()
                    .toolbar(.hidden, for: .navigationBar)
                    .statusBar(hidden: true)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .toolbar { toolbarContent }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAddRecord) {
            AddRecordView()
        }
        .onAppear { previousCount = records.count }
        .onChange(of: records.count) { _, newCount in
            trackInsert(newCount)
        }
    }

    // MARK: - Timeline List

    /// Records grouped by calendar day, newest section first.
    private var groupedRecords: [(Date, [Record])] {
        let grouped = Dictionary(grouping: records) { record in
            Calendar.current.startOfDay(for: record.timestamp)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    private var timelineList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // ── Journal‑style header ─────────────────────
                    HomeHeaderView(recordCount: records.count)

                    ForEach(groupedRecords.indices, id: \.self) { sectionIndex in
                        let (date, sectionRecords) = groupedRecords[sectionIndex]

                        DaySectionHeader(date: date, isHighlighted: date == highlightedDate)
                            .id(date)   // enables scroll‑to‑date

                        ForEach(Array(sectionRecords.enumerated()),
                                id: \.element.id) { index, record in
                            let isLastInSection = index == sectionRecords.count - 1
                            let isLastOverall = isLastInSection
                                && sectionIndex == groupedRecords.count - 1

                            NavigationLink(
                                destination: RecordDetailView(record: record)
                            ) {
                                TimelineCell(
                                    record: record,
                                    isLast: isLastOverall,
                                    isNew: record.id == newRecordID,
                                    heroNamespace: heroNamespace,
                                    heroFilename: heroPhoto?.filename,
                                    onHeroTap: startHeroTransition
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, AppTheme.spacing.large)
            }
            .onChange(of: scrollToDate) { _, newDate in
                guard let date = newDate else { return }
                // Small delay lets the tab transition settle before scrolling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo(date, anchor: .top)
                    }
                    highlightedDate = date
                    // Clear highlight after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            highlightedDate = nil
                        }
                    }
                }
                // Consume the scroll request
                scrollToDate = nil
            }
        }
    }

    // MARK: - Hero Overlay

    private func heroOverlay(_ hero: HeroPhotoState) -> some View {
        PhotoViewer(
            imagePaths: hero.paths,
            initialIndex: hero.index,
            namespace: heroNamespace,
            heroID: hero.filename,
            onDismiss: dismissHero
        )
        .transition(.opacity)
        .zIndex(100)
    }

    // MARK: - Hero Transition

    private struct HeroPhotoState {
        let paths: [String]
        let index: Int
        let filename: String
    }

    private func startHeroTransition(paths: [String], index: Int) {
        let filename = paths[index]
        heroPhoto = HeroPhotoState(paths: paths, index: index, filename: filename)
    }

    private func dismissHero() {
        withAnimation(.interactiveSpring(
            response: AppTheme.animationDuration.hero,
            dampingFraction: 0.85
        )) {
            heroPhoto = nil
        }
    }

    // MARK: - Insert Animation

    private func trackInsert(_ newCount: Int) {
        if newCount > previousCount, let first = records.first {
            newRecordID = first.id
            previousCount = newCount

            let id = newRecordID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if self.newRecordID == id {
                    self.newRecordID = nil
                }
            }
        } else {
            previousCount = newCount
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showingAddRecord = true }) {
                Image(systemName: "plus")
                    .font(.title3)
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            Button(action: { selectedTab = .search }) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
            }
            .tint(.primary)
        }
    }
}

// MARK: - Preview

#Preview("Empty") {
    TimelineView(
        scrollToDate: .constant(nil),
        selectedTab: .constant(.timeline)
    )
    .modelContainer(for: Record.self, inMemory: true)
}

#Preview("With data") {
    let container = try! ModelContainer(
        for: Record.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let d1 = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let r1 = Record(text: "今天的日落很美。", mood: .happy, locationName: "海边")
    r1.timestamp = d1
    context.insert(r1)

    let r2 = Record(text: "完成了项目第一阶段。", mood: .excited)
    context.insert(r2)

    let r3 = Record(text: "一杯咖啡，一本好书。", mood: .neutral)
    r3.timestamp = Calendar.current.date(byAdding: .hour, value: -2, to: Date())!
    context.insert(r3)

    return TimelineView(
        scrollToDate: .constant(nil),
        selectedTab: .constant(.timeline)
    )
    .modelContainer(container)
}
