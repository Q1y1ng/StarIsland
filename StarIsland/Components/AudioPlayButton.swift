import SwiftUI
import AVFoundation

// MARK: - Audio Play Button

/// Reusable component for displaying and playing a single audio recording.
///
/// Used in both ``AddRecordView`` (with delete button) and
/// ``RecordDetailView`` (with **转文字** button).
///
/// ## Features
/// - ▶︎ / ❚❚ play‑pause toggle with duration label (`MM:SS`)
/// - **转文字** button (optional, ``RecordDetailView`` only)
/// - Delete button (optional, ``AddRecordView`` only)
/// - Auto‑reset when playback finishes
struct AudioPlayButton: View {
    let audioPath: String
    var showTranscribe: Bool = false
    var onTranscribe: ((String) -> Void)?
    var onDelete: (() -> Void)?

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var duration: TimeInterval = 0

    // MARK: - Body

    var body: some View {
        HStack(spacing: AppTheme.spacing.medium) {
            // Play / pause toggle
            Button(action: togglePlay) {
                Image(systemName: isPlaying
                    ? "pause.circle.fill"
                    : "play.circle.fill"
                )
                .font(.title3)
                .foregroundStyle(.blue)
            }
            .disabled(player == nil)

            // Duration label
            Text(formatDuration(duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            // Transcribe button (RecordDetailView only)
            if showTranscribe, let onTranscribe {
                Button("转文字") {
                    transcribe(callback: onTranscribe)
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }

            // Delete button (AddRecordView only)
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .background(Circle().fill(.black.opacity(0.5)))
                }
            }
        }
        .padding(.vertical, AppTheme.spacing.xxsmall)
        .task(priority: .background) {
            await loadAudio()
        }
        .onDisappear {
            stopPlay()
        }
    }

    // MARK: - Playback

    private func loadAudio() async {
        let url = AudioStorageService.url(for: audioPath)
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = playerDelegate
        player.prepareToPlay()
        await MainActor.run {
            self.player = player
            self.duration = player.duration
        }
    }

    private func togglePlay() {
        guard let player else { return }

        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // Configure audio session for playback
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
        }
    }

    private func stopPlay() {
        player?.stop()
        isPlaying = false
    }

    // MARK: - Transcribe

    private func transcribe(callback: @escaping (String) -> Void) {
        Task {
            let url = AudioStorageService.url(for: audioPath)
            if let text = await SpeechService.transcribe(audioURL: url) {
                await MainActor.run {
                    callback(text)
                }
            }
        }
    }

    // MARK: - Helpers

    private var playerDelegate: AVAudioPlayerDelegate {
        let coordinator = PlayerCoordinator(isPlaying: $isPlaying)
        return coordinator
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--:--" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Player Coordinator

/// Bridges `AVAudioPlayerDelegate` to SwiftUI state.
private class PlayerCoordinator: NSObject, AVAudioPlayerDelegate {
    private let isPlaying: Binding<Bool>

    init(isPlaying: Binding<Bool>) {
        self.isPlaying = isPlaying
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying.wrappedValue = false
        }
    }
}

// MARK: - Preview

#Preview {
    AudioPlayButton(audioPath: "preview.m4a")
        .padding()
}
