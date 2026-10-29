import Foundation

/// Short ages for the story list: "now", "5m", "3h", "2d", then the date.
enum RelativeTime {
    static func short(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<(7 * 86_400): return "\(Int(seconds / 86_400))d"
        default:
            var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .day().month(.abbreviated)
            if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
                style = style.year()
            }
            return date.formatted(style)
        }
    }

    /// "Updated just now", "Updated 5m ago".
    static func updated(_ date: Date, now: Date) -> String {
        let age = short(date, now: now)
        return age == "now" ? "Updated just now" : "Updated \(age) ago"
    }
}
