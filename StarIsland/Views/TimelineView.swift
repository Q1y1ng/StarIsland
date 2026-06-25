import SwiftUI
import SwiftData

// MARK: - Timeline View

/// Primary screen — displays records grouped by day.
///
/// Supports multi‑scale zoom (day / week / month / year) via pinch gesture.
///
/// ## Phase 4.2 additions
/// - ``TimelineZoomLevel`` enum with pinch‑to‑zoom
/// - Quick‑edit sheet on long‑press
/// - Day counter ("已记录: 第 X 天")
/// - Week / Month / Year overview modes
struct TimelineView: View {
    @Binding var scrollToDate: Date?
    @Binding var selectedTab: AppTab

    @Query(
        filter: #Predicate<Record> { !$0.isTrashed },
        sort: \Record.timestamp, order: .reverse
    )
    private var records: [Record]

    @AppStorage("timeline_zoom_level") private var zoomLevel: TimelineZoomLevel = .day

    // Day‑mode state
    @State private var showingAddRecord = false
    @State private var previousCount = 0
    @State private var newRecordID: UUID?

    // Hero transition
    @Namespace private var heroNamespace
    @State private var heroPhoto: HeroPhotoState?

    // Scroll highlight
    @State private var highlightedDate: Date?

    // Quick edit
    @State private var quickEditRecord: Record?

    // Developer credit
    @State private var showDevCredit = false

    private let calendar = Calendar.current

    // MARK: - Body

    var body: some View {
        ZStack {
            switch zoomLevel {
            case .day:   dayContent
            case .week:  weekContent
            case .month: monthContent
            case .year:  yearContent
            }

            // Hero overlay (day mode only)
            if zoomLevel == .day, let hero = heroPhoto {
                heroOverlay(hero)
                    .ignoresSafeArea()
                    .toolbar(.hidden, for: .navigationBar)
                    .statusBar(hidden: true)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .simultaneousGesture(magnificationGesture)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: zoomLevel)
        .toolbar { toolbarContent }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAddRecord) {
            AddRecordView()
        }
        .sheet(item: $quickEditRecord) { record in
            QuickEditSheet(record: record)
        }
        .onAppear { previousCount = records.count }
        .onChange(of: records.count) { _, newCount in
            trackInsert(newCount)
        }
    }

    // MARK: - Day Content

    private var dayContent: some View {
        Group {
            if records.isEmpty {
                EmptyStateView()
            } else {
                dayList
            }
        }
    }

    /// Full timeline with grouped records (original behaviour).
    private var dayList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // ── Journal‑style header ─────────────────────
                    HomeHeaderView(
                        recordCount: records.count,
                        firstRecordDate: records.last?.createdAt,
                        zoomLevel: .day
                    )

                    ForEach(groupedRecords.indices, id: \.self) { sectionIndex in
                        let (date, sectionRecords) = groupedRecords[sectionIndex]

                        DaySectionHeader(date: date, isHighlighted: date == highlightedDate)
                            .id(date)

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
                                    onHeroTap: startHeroTransition,
                                    onLongPress: { quickEditRecord = $0 }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // ── Developer credit (subtle footer) ──────────
                    devCreditFooter
                }
                .padding(.vertical, AppTheme.spacing.large)
            }
            .onChange(of: scrollToDate) { _, newDate in
                guard let date = newDate else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo(date, anchor: .top)
                    }
                    highlightedDate = date
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            highlightedDate = nil
                        }
                    }
                }
                scrollToDate = nil
            }
        }
    }

    // MARK: - Week Content

    private var weekContent: some View {
        VStack(spacing: 0) {
            HomeHeaderView(
                recordCount: weekRecordCount,
                firstRecordDate: records.last?.createdAt,
                zoomLevel: .week,
                statsLine: weekStatsLine,
                subtitleOverride: weekDateRangeText
            )

            WeekView(records: records) { date in
                zoomToDay(date)
            }
        }
    }

    // MARK: - Month Content

    private var monthContent: some View {
        VStack(spacing: 0) {
            HomeHeaderView(
                recordCount: monthRecordCount,
                firstRecordDate: records.last?.createdAt,
                zoomLevel: .month,
                statsLine: monthStatsLine,
                subtitleOverride: nil
            )

            MonthView(records: records) { date in
                zoomToDay(date)
            }
        }
    }

    // MARK: - Year Content

    private var yearContent: some View {
        VStack(spacing: 0) {
            HomeHeaderView(
                recordCount: records.count,
                firstRecordDate: records.last?.createdAt,
                zoomLevel: .year,
                statsLine: yearStatsLine,
                subtitleOverride: nil
            )

            yearGrid

            Spacer(minLength: AppTheme.spacing.huge)
        }
    }

    /// Embarks the existing ``ContributionGridView`` for year overview.
    private var yearGrid: some View {
        let counts = yearRecordCounts
        let weeks = CalendarService.generateYear(currentYear, recordCounts: counts)

        return ContributionGridView(weeks: weeks, year: currentYear) { date in
            zoomToDay(date)
        }
        .padding(.horizontal, AppTheme.spacing.xlarge)
    }

    // MARK: - Zoom Computation

    /// Zoom into day view and scroll to a specific date.
    private func zoomToDay(_ date: Date) {
        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86)) {
            zoomLevel = .day
        }
        // Scroll to the date after the zoom transition settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            scrollToDate = date
            highlightedDate = date
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeOut(duration: 0.3)) {
                    highlightedDate = nil
                }
            }
        }
    }

    // MARK: - Computed Data (Day Grouping)

    /// Records grouped by calendar day, newest section first.
    private var groupedRecords: [(Date, [Record])] {
        let grouped = Dictionary(grouping: records) { record in
            Calendar.current.startOfDay(for: record.timestamp)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    // MARK: - Computed Data (Zoom)

    private var currentYear: Int {
        calendar.component(.year, from: Date())
    }

    private var yearRecordCounts: [Date: Int] {
        var counts: [Date: Int] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.timestamp)
            counts[day, default: 0] += 1
        }
        return counts
    }

    // MARK: Week computed

    private var weekRecordCount: Int {
        let today = Date()
        guard let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        ) else { return 0 }
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return 0 }
        return records.filter { $0.timestamp >= weekStart && $0.timestamp < weekEnd }.count
    }

    private var weekDateRangeText: String {
        let today = Date()
        guard let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        ) else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "MM/dd"
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return "" }
        return "\(fmt.string(from: weekStart)) — \(fmt.string(from: weekEnd))"
    }

    private var weekStatsLine: String {
        let count = weekRecordCount
        return count == 0 ? "本周暂无记录" : "\(count) 条记录"
    }

    // MARK: Month computed

    private var monthRecordCount: Int {
        let now = Date()
        let y = calendar.component(.year, from: now)
        let m = calendar.component(.month, from: now)
        return records.filter {
            calendar.component(.year, from: $0.timestamp) == y
            && calendar.component(.month, from: $0.timestamp) == m
        }.count
    }

    private var monthStatsLine: String {
        let count = monthRecordCount
        if count == 0 { return "本月暂无记录" }
        // Count days with records this month
        let now = Date()
        let y = calendar.component(.year, from: now)
        let m = calendar.component(.month, from: now)
        let days = Set(records.filter {
            calendar.component(.year, from: $0.timestamp) == y
            && calendar.component(.month, from: $0.timestamp) == m
        }.map { calendar.startOfDay(for: $0.timestamp) })
        return "\(count) 条记录 · \(days.count) 天"
    }

    // MARK: Year computed

    private var yearStatsLine: String {
        let year = currentYear
        let count = records.filter { calendar.component(.year, from: $0.timestamp) == year }.count
        return count == 0 ? "今年暂无记录" : "今年已记录 \(count) 条"
    }

    // MARK: - Developer Credit

    private var devCreditFooter: some View {
        VStack(spacing: AppTheme.spacing.xxsmall) {
            Divider()
                .padding(.horizontal, AppTheme.spacing.xlarge)

            Text("Made by HEAOZIE")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .padding(.top, AppTheme.spacing.medium)
                .padding(.bottom, AppTheme.spacing.xxlarge)
        }
    }

    // MARK: - Magnification Gesture

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onEnded { scale in
                if scale > 1.3 {
                    // Spread → broader timeline scale
                    switch zoomLevel {
                    case .day:   zoomLevel = .week
                    case .week:  zoomLevel = .month
                    case .month: zoomLevel = .year
                    case .year:  break
                    }
                } else if scale < 0.75 {
                    // Pinch → narrower timeline scale
                    switch zoomLevel {
                    case .year:  zoomLevel = .month
                    case .month: zoomLevel = .week
                    case .week:  zoomLevel = .day
                    case .day:   break
                    }
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
