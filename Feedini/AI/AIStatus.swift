import Foundation
import Observation

/// What the AI is doing, for the status line and Settings → AI.
@MainActor
@Observable
final class AIStatus {
    enum State: Equatable, Sendable {
        case idle
        case off
        /// Organizing this many new articles.
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
        case .organizing(let count): count == 1 ? "Organizing 1 new article…" : "Organizing \(count) new articles…"
        case .unavailable(let reason): "AI unavailable: \(reason)"
        case .idle, .off:
            switch summarizing.count {
            case 0: nil
            case 1: "Summarizing 1 story…"
            case let count: "Summarizing \(count) stories…"
            }
        }
    }

    /// Whether the AI is busy (organizing or summarizing).
    var isWorking: Bool {
        if case .organizing = state { return true }
        return !summarizing.isEmpty
    }
}
