import SwiftUI

// MARK: - Mood

/// Typed mood selection replacing the Phase 1 string-based approach.
///
/// Stored in SwiftData via `Codable` conformance.  Existing records with a
/// string mood will **not** auto-migrate — see `Record` migration notes.
enum Mood: String, Codable, CaseIterable, Sendable {
    case happy
    case neutral
    case sad
    case tired
    case excited

    // MARK: - Display Properties

    var emoji: String {
        switch self {
        case .happy:   "😊"
        case .neutral: "😐"
        case .sad:     "😢"
        case .tired:   "😴"
        case .excited: "🔥"
        }
    }

    var title: String {
        switch self {
        case .happy:   "开心"
        case .neutral: "平静"
        case .sad:     "难过"
        case .tired:   "疲惫"
        case .excited: "激动"
        }
    }

    /// SF Symbol name matching the mood.
    var symbol: String {
        switch self {
        case .happy:   "face.smiling"
        case .neutral: "face.neutral"
        case .sad:     "face.dashed"
        case .tired:   "zzz"
        case .excited: "flame"
        }
    }

    /// Apple system colour — never custom.
    var color: Color {
        switch self {
        case .happy:   .yellow
        case .neutral: .secondary
        case .sad:     .blue
        case .tired:   .purple
        case .excited: .orange
        }
    }
}
