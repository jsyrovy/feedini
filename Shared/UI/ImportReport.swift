import Foundation

/// What an OPML import did, for a report: added, not added with the reason, or why it failed.
struct ImportReport: Identifiable {
    let id = UUID()
    var added = 0
    var skipped: [(title: String, address: String, reason: String)] = []
    var error: String?
    /// The errors as text for the clipboard.
    var errorReport: String?

    init(result: FeedSubscriber.ImportResult) {
        added = result.added.count
        skipped = result.skipped.map { ($0.entry.title, $0.entry.feedURL, $0.failure.message) }
        errorReport = result.errorReport
    }

    init(error: String) {
        self.error = error
        errorReport = error
    }
}
