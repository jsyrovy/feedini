import Foundation
import Observation

/// What the AI is doing, for the status line and Settings → AI.
@MainActor
@Observable
final class AIStatus {
    enum State: Equatable, Sendable {
        case idle
        case off
        /// Organizing this many articles (unread ones, and read ones still in the attach window).
        case organizing(Int)
        /// AI can't run until something changes (no claude, a failing CLI).
        case unavailable(String)
    }

    struct Call: Equatable, Sendable, Identifiable {
        var id = UUID()
        var date: Date
        var step: String
        var stats: ClaudeCallStats?
        var error: String?
    }

    static let keptCalls = 20

    private(set) var state = State.idle
    /// Newest first.
    private(set) var calls: [Call] = []
    /// Stories whose summary is being written.
    private(set) var summarizing = Set<Story.ID>()
    /// Why a story has no summary after repeated attempts.
    private(set) var summaryErrors: [Story.ID: String] = [:]
    /// The work on source pages, for "Summarizing page…".
    let pages: PageStatus

    init(pages: PageStatus = PageStatus()) {
        self.pages = pages
    }

    func setSummarizing(_ stories: Set<Story.ID>) {
        if summarizing != stories {
            summarizing = stories
        }
    }

    func setSummaryError(_ error: String, for story: Story.ID) {
        summaryErrors[story] = error
    }

    func clearSummaryErrors() {
        if !summaryErrors.isEmpty {
            summaryErrors = [:]
        }
    }

    func set(_ state: State) {
        if self.state != state {
            self.state = state
        }
    }

    func record(_ call: Call) {
        calls.insert(call, at: 0)
        if calls.count > Self.keptCalls {
            calls.removeLast(calls.count - Self.keptCalls)
        }
    }

    /// For the status line under the story list; `nil` when there is nothing to say.
    var message: String? {
        switch state {
        case .organizing(let count): count == 1 ? "Organizing 1 article…" : "Organizing \(count) articles…"
        case .unavailable: state.problem
        case .idle, .off:
            switch summarizing.count {
            case 0: isSummarizingPage ? "Summarizing page…" : nil
            case 1: "Summarizing 1 story…"
            case let count: "Summarizing \(count) stories…"
            }
        }
    }

    /// Whether the AI is busy (organizing or summarizing stories or pages).
    var isWorking: Bool {
        if case .organizing = state { return true }
        return !summarizing.isEmpty || isSummarizingPage
    }

    private var isSummarizingPage: Bool {
        pages.isSummarizing
    }
}

extension AIStatus.State {
    static let offMessage = "AI is off (Settings → AI)."

    /// Why AI can't run; `nil` when it can.
    var problem: String? {
        switch self {
        case .off: Self.offMessage
        case .unavailable(let reason): "AI unavailable: \(reason)"
        case .idle, .organizing: nil
        }
    }
}
