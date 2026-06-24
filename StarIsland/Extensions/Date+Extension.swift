import Foundation

// MARK: - Date Convenience Extensions

extension Date {
    /// e.g. "2026-06-24 23:57:13"
    var fullDateTime: String {
        DateFormatterManager.shared.fullDateTime(from: self)
    }

    /// e.g. "23:57:13"
    var timeOnly: String {
        DateFormatterManager.shared.timeOnly(from: self)
    }

    /// e.g. "2026年06月24日"
    var dayTitle: String {
        DateFormatterManager.shared.dayTitle(from: self)
    }

    /// e.g. "星期三"
    var weekday: String {
        DateFormatterManager.shared.weekday(from: self)
    }
}
