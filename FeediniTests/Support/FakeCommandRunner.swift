import Foundation
import Synchronization

@testable import Feedini

/// A `CommandRunning` that answers every call with the next canned reply (the last one repeats) and records the
/// calls.
final class FakeCommandRunner: CommandRunning {
    struct Call: Sendable {
        var executable: URL
        var arguments: [String]
        var input: Data?
        var timeout: Duration

        /// The value following a flag, e.g. `value(of: "--model")`.
        func value(of flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        /// The stdin payload as a JSON object.
        var payload: [String: Any] {
            input.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        }
    }

    enum Reply: Sendable {
        case output(ProcessOutput)
        case error(ProcessRunnerError)

        static func stdout(_ text: String, exitStatus: Int32 = 0) -> Reply {
            .output(ProcessOutput(exitStatus: exitStatus, stdout: Data(text.utf8), stderr: Data()))
        }

        static func fixture(_ name: String) throws -> Reply {
            .output(ProcessOutput(exitStatus: 0, stdout: try Fixture.data(name), stderr: Data()))
        }

        /// A successful envelope with the given structured output.
        static func structured(_ json: String, costUSD: Double = 0.001, durationMs: Int = 1000) -> Reply {
            .stdout(
                """
                {"type":"result","subtype":"success","is_error":false,"duration_ms":\(durationMs),\
                "duration_api_ms":\(durationMs - 100),"result":"","total_cost_usd":\(costUSD),\
                "usage":{"output_tokens":100},"structured_output":\(json)}
                """)
        }
    }

    private let state: Mutex<(replies: [Reply], calls: [Call])>
    private let handler: (@Sendable (Call) -> Reply)?

    init(_ replies: [Reply]) {
        state = Mutex((replies, []))
        handler = nil
    }

    /// Answers every call with what `handler` returns for it.
    init(handler: @escaping @Sendable (Call) -> Reply) {
        state = Mutex(([], []))
        self.handler = handler
    }

    var calls: [Call] {
        state.withLock { $0.calls }
    }

    func run(_ executable: URL, arguments: [String], input: Data?, timeout: Duration) async throws -> ProcessOutput {
        let call = Call(executable: executable, arguments: arguments, input: input, timeout: timeout)
        let reply = state.withLock { state -> Reply? in
            state.calls.append(call)
            guard handler == nil else { return nil }
            return state.replies.count > 1 ? state.replies.removeFirst() : state.replies.first
        }
        switch reply ?? handler?(call) ?? .stdout("") {
        case .output(let output): return output
        case .error(let error): throw error
        }
    }
}
