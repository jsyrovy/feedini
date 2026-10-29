import Foundation
import Testing

@testable import Feedini

struct AIUsageTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    private let stats = ClaudeCallStats(
        model: "claude-haiku-5-5", durationMs: 1500, costUSD: 0.002)

    @Test func addsCallsToTheirDay() {
        var library = Library()
        library.recordAICall(at: .hours(0), stats: stats, calendar: calendar)
        library.recordAICall(at: .hours(1), stats: stats, calendar: calendar)
        library.recordAICall(at: .hours(2), stats: nil, calendar: calendar)
        // 23:00 UTC is already the next day in Prague.
        library.recordAICall(at: .hours(11), stats: stats, calendar: calendar)

        #expect(
            library.usage == [
                AIUsageDay(day: "2026-10-29", calls: 3, failures: 1, durationMs: 3000, costUSD: 0.004),
                AIUsageDay(day: "2026-10-30", calls: 1, failures: 0, durationMs: 1500, costUSD: 0.002),
            ])
    }

    @Test func keepsTheLastThirtyDays() {
        var library = Library()
        for day in 0..<40 {
            library.recordAICall(at: .hours(Double(day) * 24), stats: stats, calendar: calendar)
        }
        #expect(library.usage.count == Library.usageDays)
        #expect(library.usage.first?.day == "2026-11-08")
        #expect(library.usage.last?.day == "2026-12-07")
    }

    @Test func oldFilesWithoutUsageStillLoad() throws {
        let json = #"{"feeds":[],"articles":[],"stories":[],"topics":[],"tombstones":[]}"#
        let library = try JSONDecoder().decode(Library.self, from: Data(json.utf8))
        #expect(library.usage.isEmpty)
    }
}
