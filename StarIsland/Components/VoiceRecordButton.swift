import SwiftUI
import AVFoundation

// MARK: - Voice Record Button

/// Persistent audio recording button.
///
/// Records AAC (.m4a) to a temporary file, saves a copy via
/// ``AudioStorageService``, then calls `onRecordingComplete` with the
/// permanent filename.
///
/// ## States
/// - **Idle** – circular mic icon, tap to start recording
/// - **Recording** – red dot + elapsed time (`MM:SS`) + stop button
///
/// The recording is **not** automatically transcribed.  Transcription is
/// triggered later by the user via the **转文字** button on each audio item.
///
/// ## Permission
/// Only `NSMicrophoneUsageDescription` is required.  Speech recognition
/// permission is requested by ``AudioPlayButton`` when the user taps
/// **转文字**.
struct VoiceRecordButton: View {
    let onRecordingComplete: (String) -> Void

    @State private var phase: Phase = .idle
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var elapsedTime: TimeInterval = 0
    @State private var showingPermissionAlert = false

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    // MARK: - Body

    var body: some View {
        switch phase {
        case .idle:
            Button(action: startRecording) {
                Circle()
                    .fill(Color(.systemGray6))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "mic.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
            }

        case .recording:
            HStack(spacing: AppTheme.spacing.small) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)

                Text(elapsedTime.formatted(.time(pattern: .minuteSecond)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.red)
                    .contentTransition(.numericText())
                    .onReceive(timer) { _ in
                        if let recorder = audioRecorder, recorder.isRecording {
                            elapsedTime = recorder.currentTime
                        }
                    }

                Button(action: stopRecording) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, AppTheme.spacing.medium)
            .padding(.vertical, AppTheme.spacing.small)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
        }
    }

    // MARK: - Recording

    private func startRecording() {
        Task {
            let micGranted = await requestMicrophonePermission()
            guard micGranted else {
                await MainActor.run { showingPermissionAlert = true }
                return
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("recording_\(UUID().uuidString).m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]

            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .default)
                try session.setActive(true)

                let recorder = try AVAudioRecorder(url: url, settings: settings)
                recorder.record()

                await MainActor.run {
                    audioRecorder = recorder
                    recordingURL = url
                    elapsedTime = 0
                    phase = .recording
                }
            } catch {
                await MainActor.run { phase = .idle }
            }
        }
        .alert("需要麦克风权限", isPresented: $showingPermissionAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请在设置中允许 StarIsland 使用麦克风权限。")
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil

        guard let url = recordingURL else {
            phase = .idle
            return
        }
        recordingURL = nil

        Task {
            guard let data = try? Data(contentsOf: url),
                  let filename = AudioStorageService.save(data)
            else {
                try? FileManager.default.removeItem(at: url)
                await MainActor.run { phase = .idle }
                return
            }

            try? FileManager.default.removeItem(at: url)

            await MainActor.run {
                phase = .idle
                onRecordingComplete(filename)
            }
        }
    }

    // MARK: - Permission

    private func requestMicrophonePermission() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:    return true
        case .denied:     return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default: return false
        }
    }

    // MARK: - Phase

    private enum Phase {
        case idle
        case recording
    }
}

// MARK: - Preview

#Preview {
    VoiceRecordButton(onRecordingComplete: { print($0) })
}
