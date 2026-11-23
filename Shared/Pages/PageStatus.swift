import Foundation
import Observation

/// The work on articles' source pages (P, Save Link, and on the Mac T and Shift+S): what is being loaded or
/// summarized, and why it failed; nothing once done. It is the only record of the work, so the detail and the rows
/// show it.
@MainActor
@Observable
final class PageStatus {
    /// The work on an article's source page.
    struct Work: Equatable, Sendable {
        enum Phase: Equatable, Sendable {
            case loading
            /// Writing its summary (only on the Mac, `PageSummaryQueue`).
            case summarizing
            case failed(String)
        }

        var phase: Phase
        /// Whether a summary was asked for (P only loads the page).
        var summary: Bool

        /// Loading or summarizing, not failed.
        var isRunning: Bool {
            if case .failed = phase { false } else { true }
        }
    }

    private(set) var pages: [Article.ID: Work] = [:]

    subscript(_ id: Article.ID) -> Work? { pages[id] }

    func set(_ work: Work?, for article: Article.ID) {
        if pages[article] != work {
            pages[article] = work
        }
    }

    /// Records that the work failed, keeping whether a summary was asked for.
    func fail(_ article: Article.ID, _ message: String) {
        set(Work(phase: .failed(message), summary: pages[article]?.summary ?? false), for: article)
    }

    /// Whether a page summary is being written.
    var isSummarizing: Bool {
        pages.values.contains { $0.phase == .summarizing }
    }
}
