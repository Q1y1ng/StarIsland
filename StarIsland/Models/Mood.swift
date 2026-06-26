import SwiftUI

// MARK: - Mood

/// Typed mood selection with 16 emoji options.
///
/// Stored in SwiftData via `Codable` conformance.  Existing records with a
/// string mood will **not** auto-migrate — see `Record` migration notes.
enum Mood: String, Codable, CaseIterable, Sendable {
    case happy
    case excited
    case content
    case surprised

    case neutral
    case relaxed

    case celebrating
    case touched

    case sad
    case lost

    case angry
    case furious

    case anxious
    case nervous

    case tired
    case sleepy

    // MARK: - Display Properties

    var emoji: String {
        switch self {
        case .happy:       "😊"
        case .excited:     "😄"
        case .content:     "😁"
        case .surprised:   "🤩"

        case .neutral:     "😌"
        case .relaxed:     "🙂"

        case .celebrating: "🥳"
        case .touched:     "🥰"

        case .sad:         "😭"
        case .lost:        "😢"

        case .angry:       "😤"
        case .furious:     "😡"

        case .anxious:     "😰"
        case .nervous:     "😥"

        case .tired:       "😴"
        case .sleepy:      "🥱"
        }
    }

    var title: String {
        switch self {
        case .happy:       "开心"
        case .excited:     "兴奋"
        case .content:     "满足"
        case .surprised:   "惊喜"

        case .neutral:     "平静"
        case .relaxed:     "放松"

        case .celebrating: "庆祝"
        case .touched:     "感动"

        case .sad:         "难过"
        case .lost:        "失落"

        case .angry:       "生气"
        case .furious:     "愤怒"

        case .anxious:     "焦虑"
        case .nervous:     "紧张"

        case .tired:       "疲惫"
        case .sleepy:      "困倦"
        }
    }

    /// SF Symbol name matching the mood.
    var symbol: String {
        switch self {
        case .happy:       "face.smiling"
        case .excited:     "face.smiling"
        case .content:     "face.smiling"
        case .surprised:   "exclamationmark.circle"

        case .neutral:     "face.neutral"
        case .relaxed:     "face.smiling"

        case .celebrating: "party.popper"
        case .touched:     "heart"

        case .sad:         "face.dashed"
        case .lost:        "face.dashed"

        case .angry:       "exclamationmark.triangle"
        case .furious:     "exclamationmark.triangle"

        case .anxious:     "questionmark.circle"
        case .nervous:     "questionmark.circle"

        case .tired:       "zzz"
        case .sleepy:      "moon.zzz"
        }
    }

    /// Apple system colour — never custom.
    var color: Color {
        switch self {
        case .happy:       .yellow
        case .excited:     .orange
        case .content:     .green
        case .surprised:   .pink

        case .neutral:     .secondary
        case .relaxed:     .mint

        case .celebrating: .orange
        case .touched:     .pink

        case .sad:         .blue
        case .lost:        .indigo

        case .angry:       .red
        case .furious:     .red

        case .anxious:     .purple
        case .nervous:     .purple

        case .tired:       .purple
        case .sleepy:      .teal
        }
    }
}
