import SwiftUI

// MARK: - Voice Record Button
//
// Placeholder — Phase 4.6 (not yet implemented).
// Will provide microphone-based voice recording for journal entries.
// Reserved: do not remove.
struct VoiceRecordButton: View {
    var body: some View {
        Button {
            // TODO: Phase 4.6
        } label: {
            Image(systemName: "mic.fill")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
        .disabled(true)
    }
}

#Preview {
    VoiceRecordButton()
}
