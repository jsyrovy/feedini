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
        case .idle, .off: nil
        case .organizing(let count): count == 1 ? "Organizing 1 new article…" : "Organizing \(count) new articles…"
        case .unavailable(let reason): "AI unavailable: \(reason)"
        }
    }
}
