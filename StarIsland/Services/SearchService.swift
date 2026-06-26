import Foundation
import SwiftData

// MARK: - Search Service

/// Filters records in-memory across three dimensions:
///
/// 1. **Text** — matches against `Record.text` (case-insensitive)
/// 2. **Location** — matches against `Record.locationName`
/// 3. **Mood** — matches emoji tokens (😊 😄 😁 🤩 😌 🙂 🥳 🥰 😭 😢 😤 😡 😰 😥 😴 🥱)
///    against the record's mood
///
/// All tokens are AND'd: a record must match **every** token to appear.
/// Multiple dimensions per token are OR'd (text OR location OR mood).
///
/// ```swift
/// SearchService.search("晚霞 学校 😊", among: records)
/// ```
enum SearchService {
    /// The set of emoji strings that map to `Mood` cases.
    private static let moodEmojis: Set<String> = Set(Mood.allCases.map(\.emoji))

    /// Filter `records` to those matching `query`.
    /// - Returns: Matching records, newest-first.  Returns all records when
    ///   `query` is empty.
    static func search(_ query: String, among records: [Record]) -> [Record] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokens = trimmed.split(separator: " ").map(String.init)

        return records.filter { record in
            tokens.allSatisfy { token in
                matches(token: token, record: record)
            }
        }
    }

    // MARK: - Match

    private static func matches(token: String, record: Record) -> Bool {
        // Mood match
        if moodEmojis.contains(token),
           let mood = record.mood {
            return mood.emoji == token
        }

        // Text match
        if record.text.localizedCaseInsensitiveContains(token) {
            return true
        }

        // Location match
        if let location = record.locationName,
           location.localizedCaseInsensitiveContains(token) {
            return true
        }

        return false
    }
}
