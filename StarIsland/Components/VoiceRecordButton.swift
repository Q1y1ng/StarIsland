import SwiftUI
import AVFoundation

// MARK: - Voice Record Button

/// Minimal‑viable‑product voice recording button.
///
/// Tapping starts recording; tapping again stops, transcribes via
/// ``SpeechService``, and calls `onTranscription` with the result.
///
/// ## Permission flow
/// 1. Microphone permission (`AVAudioSession.requestRecordPermission`)
/// 2. Speech recognition permission (`SFSpeechRecognizer.requestAuthorization`)
///
/// If either is denied the button shows an alert guiding the user to Settings.
///
/// ## States
/// - Idle           – mic icon, enabled
/// - Recording      – red stop icon, pulsing animation
/// - Processing     – mic icon, disabled (transcribing)
///
/// ## Requirements
/// - `NSMicrophoneUsageDescription` in Info.plist
/// - `NSSpeechRecognitionUsageDescription` in Info.plist
struct VoiceRecordButton: View {
    let onTranscription: (String) -> Void

    @State private var phase: Phase = .idle
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var showingPermissionAlert = false

    // MARK: - Body

    var body: some View {
        Button {
            switch phase {
            case .idle:       startRecording()
            case .recording:  stopRecording()
            case .processing: break
            }
        } label: {
            Image(systemName: phase == .recording ? "stop.circle.fill" : "mic.fill")
                .font(.title3)
                .foregroundStyle(micColor)
        }
        .disabled(phase == .processing)
        .alert("需要权限", isPresented: $showingPermissionAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请在设置中允许 StarIsland 使用麦克风和语音识别权限。")
        }
    }

    private var micColor: Color {
        switch phase {
        case .idle:      return .primary
        case .recording: return .red
        case .processing: return .secondary
        }
    }

    // MARK: - Recording

    private func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()

        Task {
            // ── 1. Microphone permission ──────────────────────
            let micGranted = await requestMicrophonePermission()
            guard micGranted else {
                await MainActor.run { showingPermissionAlert = true }
                return
            }

            // ── 2. Speech recognition permission ──────────────
            let speechGranted = await SpeechService.requestAuthorization()
            guard speechGranted else {
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
                try audioSession.setCategory(.record, mode: .default)
                try audioSession.setActive(true)

                let recorder = try AVAudioRecorder(url: url, settings: settings)
                recorder.record()

                await MainActor.run {
                    audioRecorder = recorder
                    recordingURL = url
                    phase = .recording
                }
            } catch {
                print("[Voice] recording setup failed:", error.localizedDescription)
                await MainActor.run { phase = .idle }
            }
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        phase = .processing

        guard let url = recordingURL else {
            phase = .idle
            return
        }
        recordingURL = nil

        Task {
            let text = await SpeechService.transcribe(audioURL: url)
            try? FileManager.default.removeItem(at: url)
            await MainActor.run {
                phase = .idle
                if let text, !text.isEmpty {
                    print("[Voice] transcription:", text.prefix(50))
                    onTranscription(text)
                }
            }
        }
    }

    // MARK: - Permission

    private func requestMicrophonePermission() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Phase

    private enum Phase {
        case idle
        case recording
        case processing
    }
}

// MARK: - Preview

#Preview {
    VoiceRecordButton(onTranscription: { print($0) })
}
