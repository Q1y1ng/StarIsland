import SwiftUI

// MARK: - Home Header View

/// Large-formatted date header shown at the top of the timeline.
///
/// Replaces the navigation bar title.  Apple Journal style:
/// ```
/// 今天
/// 2026年06月24日 星期三
/// 3 条记录
/// ```
struct HomeHeaderView: View {
    let recordCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xsmall) {
            Text("今天")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            HStack(spacing: AppTheme.spacing.medium) {
                Text(Date().dayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(Date().weekday)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(recordCountText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, AppTheme.spacing.xxxsmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.spacing.xlarge)
        .padding(.top, AppTheme.spacing.xlarge)
        .padding(.bottom, AppTheme.spacing.medium)
    }

    // MARK: - Helpers

    private var recordCountText: String {
        switch recordCount {
        case 0:  "暂无记录"
        case 1:  "1 条记录"
        default: "\(recordCount) 条记录"
        }
    }
}

// MARK: - Preview

#Preview {
    HomeHeaderView(recordCount: 3)
}
