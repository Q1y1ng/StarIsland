import SwiftUI

// MARK: - Mood Selector View

/// Horizontal mood picker with Apple-system aesthetics.
///
/// Displays all `Mood` cases as labelled emoji buttons.
/// Selection is animated with a subtle scale effect.
struct MoodSelectorView: View {
    @Binding var selection: Mood?

    // MARK: - Layout Constants

    private let itemSpacing: CGFloat = 4
    private let buttonSize: CGFloat = 48

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: itemSpacing) {
                Spacer(minLength: 0)

                ForEach(Mood.allCases, id: \.self) { mood in
                    Button {
                        withAnimation(.interactiveSpring(
                            response: 0.25,
                            dampingFraction: 0.75
                        )) {
                            selection = selection == mood ? nil : mood
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(mood.emoji)
                                .font(.title2)

                            Text(mood.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: buttonSize, height: buttonSize + 8)
                        .background(selection == mood ? Color(.systemGray4) : Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .scaleEffect(selection == mood ? 1.05 : 1.0)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.spacing.xlarge)
            .padding(.vertical, AppTheme.spacing.medium)
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var mood: Mood? = .happy
    MoodSelectorView(selection: $mood)
}
