import SwiftUI

// MARK: - Search Bar View

/// Minimal search field with Apple-system styling.
///
/// Includes a magnifying-glass icon, placeholder text, and a clear button
/// when the field is non-empty.
struct SearchBarView: View {
    @Binding var text: String
    var placeholder: String = "搜索"

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppTheme.spacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            TextField(placeholder, text: $text)
                .font(.body)
                .focused($isFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, AppTheme.spacing.large)
        .padding(.vertical, AppTheme.spacing.medium)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius.standard,
                                    style: .continuous))
        .padding(.horizontal, AppTheme.spacing.xlarge)
        .padding(.vertical, AppTheme.spacing.medium)
        .onAppear { isFocused = true }
    }
}

// MARK: - Preview

#Preview {
    SearchBarView(text: .constant(""))
}
