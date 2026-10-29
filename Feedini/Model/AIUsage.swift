import Foundation

/// The AI calls of one day, for the statistics in Settings → AI.
struct AIUsageDay: Codable, Sendable, Hashable {
    /// `yyyy-MM-dd` in the local calendar.
    var day: String
    var calls = 0
    var failures = 0
    var durationMs = 0
    var costUSD = 0.0
}

extension Library {
    /// Days kept in `usage`.
    static let usageDays = 30

    /// Adds a call to the statistics of its day; `nil` stats mean the call failed. Keeps the last `usageDays` days.
    mutating func recordAICall(at date: Date, stats: ClaudeCallStats?, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        var entry = usage.first { $0.day == day } ?? AIUsageDay(day: day)
        entry.calls += 1
        if let stats {
            entry.durationMs += stats.durationMs
            entry.costUSD += stats.costUSD
        } else {
            entry.failures += 1
        }
        usage = (usage.filter { $0.day != day } + [entry]).sorted { $0.day < $1.day }.suffix(Self.usageDays)
    }
}
