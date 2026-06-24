import SwiftUI

// MARK: - Stats Card View

/// A single stat display in the Apple Health / Screen Time style.
///
/// ```
/// ┌──────────────────────────────┐
/// │  245                         │  ← large number
/// │  总记录数                     │  ← label
/// └──────────────────────────────┘
/// ```
///
/// - Large whitespace around the number.
/// - No shadows, no gradients, no background tint.
/// - System fonts throughout.
struct StatsCardView: View {
    let title: String
    let value: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xsmall) {
            // ── Value ─────────────────────────────────────────────
            Text(value)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            // ── Title ─────────────────────────────────────────────
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // ── Optional subtitle ─────────────────────────────────
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacing.xlarge)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius.statsCard, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: AppTheme.spacing.large) {
        StatsCardView(title: "总记录数", value: "245")
        StatsCardView(title: "最长连续记录", value: "47 天", subtitle: "2026-05-08 ~ 2026-06-23")
        StatsCardView(title: "平均每天", value: "2.3 条")
    }
    .padding()
}
