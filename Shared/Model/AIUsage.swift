import Foundation

/// The AI calls of one day, for the statistics in Settings → AI (recorded on the Mac: `Library.recordAICall`).
struct AIUsageDay: Codable, Sendable, Hashable {
    /// `yyyy-MM-dd` in the local calendar.
    var day: String
    var calls = 0
    var failures = 0
    var durationMs = 0
    var costUSD = 0.0
}
