import SwiftUI

// MARK: - Year Picker View

/// Minimal year navigator inspired by Apple Photos Memories.
///
/// Left / right chevrons switch the displayed year with an
/// `interactiveSpring` transition.  No WheelPicker — this is pure
/// button‑based navigation.
///
/// ```
///  <   2026   >
/// ```
struct YearPickerView: View {
    @Binding var currentYear: Int

    var body: some View {
        HStack(spacing: AppTheme.spacing.xxxlarge) {
            // ── Previous ─────────────────────────────────────────
            Button { withAnimation(.interactiveSpring) { currentYear -= 1 } } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)

            // ── Current year ──────────────────────────────────────
            Text("\(currentYear)")
                .font(.title)
                .fontWeight(.semibold)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(currentYear)))
                .animation(.interactiveSpring, value: currentYear)
                .frame(minWidth: 80)

            // ── Next ──────────────────────────────────────────────
            Button { withAnimation(.interactiveSpring) { currentYear += 1 } } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var year = Calendar.current.component(.year, from: Date())
    YearPickerView(currentYear: $year)
        .padding()
}
