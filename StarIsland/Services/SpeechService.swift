import Foundation
import Speech

// MARK: - Speech Service

/// Converts recorded audio to text using `SFSpeechRecognizer`.
///
/// ## Usage
/// ```swift
/// let text = await SpeechService.transcribe(audioURL: url)
/// ```
///
/// ## Requirements
/// - `NSSpeechRecognitionUsageDescription` in Info.plist
/// - Call ``requestAuthorization()`` once before the first transcription.
/// - User must grant speech recognition permission (system prompt on first use).
enum SpeechService {
    /// Requests speech‑recognition permission from the user.
    /// - Returns: `true` when the user has granted access.
    static func requestAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            print("[Speech] already authorized")
            return true
        case .notDetermined:
            print("[Speech] requesting authorization…")
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    let granted = status == .authorized
                    print("[Speech] authorization result:", granted)
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            print("[Speech] denied / restricted")
            return false
        @unknown default:
            print("[Speech] unknown authorization status")
            return false
        }
    }

    /// Transcribes the audio at `audioURL` using the on‑device speech recognizer.
    /// - Parameter audioURL: Local file URL of a recording (AAC/MPEG4, WAV, etc.).
    /// - Returns: The best‑guess transcription string, or `nil` on failure.
    static func transcribe(audioURL: URL) async -> String? {
        let recognizer: SFSpeechRecognizer
        if let zhRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans")) {
            recognizer = zhRecognizer
        } else {
            print("[Speech] zh-Hans recognizer not available")
            return nil
        }

        guard recognizer.isAvailable else {
            print("[Speech] recognizer not available")
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        print("[Speech] starting recognitionTask…")
        return await withCheckedContinuation { continuation in
            var didResume = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !didResume else { return }
                if let result {
                    didResume = true
                    let text = result.bestTranscription.formattedString
                    print("[Speech] transcription success:", text.prefix(50))
                    continuation.resume(returning: text)
                } else if let error {
                    didResume = true
                    let nsError = error as NSError
                    print("[Speech] transcription error: domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription) userInfo=\(nsError.userInfo)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
