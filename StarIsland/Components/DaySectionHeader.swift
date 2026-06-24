import SwiftUI

// MARK: - Day Section Header

/// Floating date header used between day groups in the timeline.
///
/// The timeline column shows a continuous vertical line bridging the
/// last record of the previous day to the first record of this day.
/// Below the header a short separator marks the section boundary.
///
/// ## Phase 3 — highlight
/// Set `isHighlighted` to `true` for a brief visual pulse after
/// a cross‑tab scroll‑to‑date (see ``TimelineView``).
struct DaySectionHeader: View {
    let date: Date
    var isHighlighted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: AppTheme.spacing.large) {
                // ── Timeline column ──────────────────────────────────
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)

                // ── Date content ─────────────────────────────────────
                VStack(alignment: .leading, spacing: AppTheme.spacing.xxxsmall) {
                    Text(date.dayTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(date.weekday)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.spacing.xlarge)
            .padding(.top, AppTheme.spacing.xxlarge)
            .padding(.bottom, AppTheme.spacing.xsmall)
            .background(
                Group {
                    if isHighlighted {
                        Color(.systemYellow)
                            .opacity(0.12)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: AppTheme.cornerRadius.medium,
                                    style: .continuous
                                )
                            )
                    }
                }
            )

            // ── Section separator ───────────────────────────────────
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
                .padding(.leading, AppTheme.spacing.xlarge + AppTheme.timeline.indicatorWidth + AppTheme.spacing.large)
                .padding(.trailing, AppTheme.spacing.xlarge)
        }
    }
}

// MARK: - Preview

#Preview("Normal") {
    DaySectionHeader(date: Date())
}

#Preview("Highlighted") {
    DaySectionHeader(date: Date(), isHighlighted: true)
}
