import Foundation
import Testing

@testable import Feedini

struct RelativeTimeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func short(hoursAgo: Double) -> String {
        RelativeTime.short(
            .hours(-hoursAgo), now: referenceDate, calendar: calendar, locale: Locale(identifier: "en_US"))
    }

    @Test func showsShortAges() {
        #expect(short(hoursAgo: 0) == "now")
        #expect(short(hoursAgo: -1) == "now")
        #expect(short(hoursAgo: 59.0 / 3600) == "now")
        #expect(short(hoursAgo: 5.0 / 60) == "5m")
        #expect(short(hoursAgo: 3.5) == "3h")
        #expect(short(hoursAgo: 49) == "2d")
    }

    @Test func showsTheDateAfterAWeek() {
        #expect(short(hoursAgo: 24 * 8) == "Oct 21")
        #expect(short(hoursAgo: 24 * 400) == "Sep 24, 2025")
    }
}
