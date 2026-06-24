import SwiftUI

// MARK: - Empty State View

/// Displayed when the timeline has zero records.
///
/// Minimal design with large whitespace — no buttons, no List.
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: AppTheme.spacing.xlarge) {
            Spacer()

            Text("🌌")
                .font(.system(size: 56))

            Text("StarIsland")
                .font(.title)
                .fontWeight(.semibold)

            Text("记录属于这一秒的故事。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    EmptyStateView()
}
