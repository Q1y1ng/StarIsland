import SwiftUI

// MARK: - Timeline Cell

/// A single row in the timeline, designed to be used inside a `LazyVStack`.
///
/// Layout (left → right):
/// ```
/// ●          23:57:13  📍地点  😊
/// │
/// │          文本内容（最多两行）
/// │
/// │          [图片网格 — 最多预览 4 张]
/// ```
///
/// ## Insert Animation
/// When `isNew` is `true` the cell performs a subtle scale + fade-in
/// animation on appear (used for Quick Capture feedback).
struct TimelineCell: View {
    let record: Record
    let isLast: Bool
    var isNew: Bool = false

    // Hero transition (forwarded to ImageGridView)
    var heroNamespace: Namespace.ID?
    var heroFilename: String?
    var onHeroTap: (([String], Int) -> Void)?

    /// Callback for quick‑edit long press.
    var onLongPress: ((Record) -> Void)?

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing.large) {
            timelineIndicator
            contentArea
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.spacing.xlarge)
        .padding(.vertical, AppTheme.spacing.medium)
        .opacity(appeared ? 1 : 0.6)
        .scaleEffect(x: appeared ? 1 : 0.97, anchor: .top)
        .onAppear { animateAppear() }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onLongPress?(record) }
        )
    }

    // MARK: - Animation

    private func animateAppear() {
        guard !appeared else { return }
        if isNew {
            withAnimation(.interactiveSpring(
                response: AppTheme.animationDuration.insert,
                dampingFraction: 0.8
            )) {
                appeared = true
            }
        } else {
            appeared = true
        }
    }

    // MARK: - Left: Timeline Indicator

    private var timelineIndicator: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(.primary)
                .frame(
                    width: AppTheme.timeline.dotSize,
                    height: AppTheme.timeline.dotSize
                )
                .padding(.top, AppTheme.spacing.small)
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)

            Rectangle()
                .fill(.separator)
                .frame(width: AppTheme.timeline.lineWidth)
                .opacity(isLast ? 0 : (appeared ? 1 : 0))
        }
        .frame(width: AppTheme.timeline.indicatorWidth)
    }

    // MARK: - Right: Content

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.small) {
            headerView
            textContent
            imagePreview
        }
    }

    private var headerView: some View {
        HStack(spacing: AppTheme.spacing.medium) {
            Text(record.timestamp.timeOnly)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if let location = record.locationName, !location.isEmpty {
                Label(location, systemImage: "location.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
            }

            if let mood = record.mood {
                Text(mood.emoji)
                    .font(.caption)
            }
        }
    }

    private var textContent: some View {
        Text(record.text)
            .font(.body)
            .lineLimit(2)
            .lineSpacing(AppTheme.spacing.xsmall)
    }

    // MARK: - Image Preview

    @ViewBuilder
    private var imagePreview: some View {
        if !record.imagePaths.isEmpty {
            ImageGridView(
                imagePaths: record.imagePaths,
                maxDisplay: 4,
                heroNamespace: heroNamespace,
                heroFilename: heroFilename,
                onTapImage: onHeroTap
            )
            .frame(maxWidth: 280)
        }
    }
}

// MARK: - Preview

#Preview("With content") {
    let record = Record(
        text: "今天在公园散步，天气很好。",
        mood: .happy,
        locationName: "中央公园"
    )
    TimelineCell(record: record, isLast: false)
        .padding(.vertical)
}

#Preview("Last item") {
    let record = Record(
        text: "最后一条记录。",
        mood: .neutral
    )
    TimelineCell(record: record, isLast: true)
        .padding(.vertical)
}
