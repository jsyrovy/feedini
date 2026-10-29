import Foundation
import Testing

@testable import Feedini

struct ClaudeClientTests {
    private struct Answer: Decodable, Equatable {
        var result: Int
    }

    private let claude = URL(fileURLWithPath: "/Users/me/.local/bin/claude")

    private func request() -> ClaudeRequest {
        ClaudeRequest(
            model: "claude-haiku-5-5", effort: "low", systemPrompt: "Double n.",
            schema: #"{"type":"object"}"#, input: Data(#"{"n":2}"#.utf8), timeout: .seconds(30))
    }

    private func client(_ runner: FakeCommandRunner, found: Bool = true) -> ClaudeClient {
        let claude = claude
        return ClaudeClient(runner: runner, locate: { found ? claude : nil })
    }

    @Test func runsTheCLIWithoutToolsAndReadsTheStructuredOutput() async throws {
        let runner = FakeCommandRunner([try .fixture("claude-success.json")])

        let (answer, stats) = try await client(runner).run(request(), as: Answer.self)

        #expect(answer == Answer(result: 4))
        #expect(
            stats
                == ClaudeCallStats(model: "claude-haiku-5-5", durationMs: 1547, costUSD: 0.0002433))
        let call = try #require(runner.calls.first)
        #expect(call.executable == claude)
        #expect(
            call.arguments == [
                "-p", "--model", "claude-haiku-5-5", "--effort", "low", "--system-prompt", "Double n.", "--safe-mode",
                "--tools", "", "--no-session-persistence", "--output-format", "json", "--json-schema",
                #"{"type":"object"}"#, "Process the input.",
            ])
        #expect(call.input == Data(#"{"n":2}"#.utf8))
        #expect(call.timeout == .seconds(30))
    }

    @Test func reportsAMissingCLI() async {
        await #expect(throws: ClaudeError.notFound) {
            try await client(FakeCommandRunner([]), found: false).run(request(), as: Answer.self)
        }
    }

    @Test func reportsErrorsOfTheCLI() async throws {
        await #expect(throws: ClaudeError.failed("Invalid API key · Please run /login")) {
            try await client(FakeCommandRunner([try .fixture("claude-error.json")])).run(request(), as: Answer.self)
        }
        await #expect(throws: ClaudeError.noStructuredOutput("I can't produce that.")) {
            try await client(FakeCommandRunner([try .fixture("claude-no-structured-output.json")])).run(
                request(), as: Answer.self)
        }
        await #expect {
            try await client(FakeCommandRunner([try .fixture("claude-wrong-shape.json")])).run(
                request(), as: Answer.self)
        } throws: { error in
            if case ClaudeError.invalidOutput = error { true } else { false }
        }
    }

    @Test func reportsBrokenOutput() async {
        let garbage = FakeCommandRunner([.stdout("Something went wrong")])
        await #expect(throws: ClaudeError.invalidEnvelope) { try await client(garbage).run(request(), as: Answer.self) }

        let crashed = FakeCommandRunner([
            .output(ProcessOutput(exitStatus: 1, stdout: Data(), stderr: Data("error: unknown option\nmore".utf8)))
        ])
        await #expect(throws: ClaudeError.exitStatus(1, "error: unknown option")) {
            try await client(crashed).run(request(), as: Answer.self)
        }

        let textOnFailure = FakeCommandRunner([.stdout("Not logged in", exitStatus: 1)])
        await #expect(throws: ClaudeError.exitStatus(1, "Not logged in")) {
            try await client(textOnFailure).run(request(), as: Answer.self)
        }

        let isError = FakeCommandRunner([.stdout(#"{"type":"result","is_error":true,"subtype":"error_max_turns"}"#)])
        await #expect(throws: ClaudeError.failed("claude reported an error (error_max_turns)")) {
            try await client(isError).run(request(), as: Answer.self)
        }
    }

    @Test func mapsRunnerErrors() async {
        await #expect(throws: ClaudeError.timedOut) {
            try await client(FakeCommandRunner([.error(.timedOut(.seconds(30)))])).run(request(), as: Answer.self)
        }
        await #expect(throws: ClaudeError.launchFailed("no such file")) {
            try await client(FakeCommandRunner([.error(.launchFailed("no such file"))])).run(
                request(), as: Answer.self)
        }
    }

    @Test func explainsErrors() {
        #expect(ClaudeError.notFound.message == "claude not found")
        #expect(ClaudeError.exitStatus(2, "").message == "claude exited with status 2")
        #expect(ClaudeError.exitStatus(2, "boom").message == "claude exited with status 2: boom")
        #expect(ClaudeError.noStructuredOutput("").message == "claude gave no structured answer")
        #expect(ClaudeError.noStructuredOutput("x").message == "claude gave no structured answer: x")
        for error in [
            ClaudeError.launchFailed("x"), .timedOut, .invalidEnvelope, .failed("x"), .invalidOutput("x"),
        ] {
            #expect(!error.message.isEmpty)
        }
        #expect(!ClaudeError.notFound.isTransient)
        #expect(!ClaudeError.launchFailed("x").isTransient)
        #expect(ClaudeError.timedOut.isTransient)
    }
}
