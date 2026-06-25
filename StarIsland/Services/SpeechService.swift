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
/// - User must grant speech recognition permission (system prompt on first use)
enum SpeechService {
    /// Transcribes the audio at `audioURL` using the on‑device speech recognizer.
    /// - Parameter audioURL: Local file URL of a recording (AAC/MPEG4, WAV, etc.).
    /// - Returns: The best‑guess transcription string, or `nil` on failure.
    static func transcribe(audioURL: URL) async -> String? {
        let recognizer: SFSpeechRecognizer
        if let zhRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans")) {
            recognizer = zhRecognizer
        } else {
            return nil
        }

        guard recognizer.isAvailable else { return nil }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { continuation in
            var didResume = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !didResume else { return }
                if let result {
                    didResume = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
