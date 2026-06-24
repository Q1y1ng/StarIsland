import Foundation

// MARK: - Date Formatter Manager

/// Single source of truth for all date formatting in the app.
///
/// Every View must call methods here rather than creating ad-hoc formatters.
/// Using a shared singleton avoids re-creating expensive `DateFormatter` instances.
final class DateFormatterManager {
    static let shared = DateFormatterManager()

    private init() {}

    // MARK: - Formatters

    private lazy var fullDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private lazy var timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private lazy var dayTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年MM月dd日"
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone.current
        return f
    }()

    private lazy var weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone.current
        return f
    }()

    // MARK: - Public API

    func fullDateTime(from date: Date) -> String {
        fullDateTimeFormatter.string(from: date)
    }

    func timeOnly(from date: Date) -> String {
        timeOnlyFormatter.string(from: date)
    }

    func dayTitle(from date: Date) -> String {
        dayTitleFormatter.string(from: date)
    }

    func weekday(from date: Date) -> String {
        weekdayFormatter.string(from: date)
    }
}
