import Foundation
import Testing

@testable import Feedini

/// Runs real processes through `/bin/sh`.
struct ProcessRunnerTests {
    private let shell = URL(fileURLWithPath: "/bin/sh")
    private let clock = ContinuousClock()
    /// Upper bound for what has to end early: far above the expected < 1 s, yet well below the `sleep 10` of the
    /// scripts, so a loaded machine doesn't fail the tests but a process left running does.
    private let promptly = Duration.seconds(5)

    private func sh(
        _ script: String, input: Data? = nil, timeout: Duration = .seconds(5), runner: ProcessRunner = ProcessRunner()
    )
        async throws -> ProcessOutput
    {
        try await runner.run(shell, arguments: ["-c", script], input: input, timeout: timeout)
    }

    @Test func collectsStdoutStderrAndExitStatus() async throws {
        let output = try await sh("printf out; printf err >&2; exit 3")
        #expect(output == ProcessOutput(exitStatus: 3, stdout: Data("out".utf8), stderr: Data("err".utf8)))
    }

    @Test func readsOutputLargerThanThePipeBuffer() async throws {
        let output = try await sh("head -c 300000 /dev/zero")
        #expect(output.exitStatus == 0)
        #expect(output.stdout.count == 300_000)
    }

    @Test func writesTheInputToStdin() async throws {
        let output = try await sh("cat", input: Data("{\"n\": 2}".utf8))
        #expect(output.stdout == Data("{\"n\": 2}".utf8))
    }

    @Test func writesInputLargerThanThePipeBuffer() async throws {
        let input = Data(repeating: UInt8(ascii: "x"), count: 1_000_000)
        let output = try await sh("wc -c | tr -d ' '", input: input)
        #expect(
            String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "1000000")
    }

    @Test func survivesACommandThatDoesNotReadItsInput() async throws {
        let input = Data(repeating: UInt8(ascii: "x"), count: 1_000_000)
        let output = try await sh("exit 4", input: input)
        #expect(output.exitStatus == 4)
    }

    @Test func stdinIsDevNull() async throws {
        // `cat` would wait forever on an inherited terminal stdin.
        let output = try await sh("cat", timeout: .seconds(2))
        #expect(output.exitStatus == 0)
        #expect(output.stdout.isEmpty)
    }

    @Test func terminatesProcessesThatExceedTheTimeout() async {
        let start = clock.now
        await #expect(throws: ProcessRunnerError.timedOut(.milliseconds(300))) {
            try await sh("sleep 10", timeout: .milliseconds(300))
        }
        #expect(clock.now - start < promptly)
    }

    @Test func killsProcessesThatIgnoreSigterm() async {
        let runner = ProcessRunner(killGracePeriod: .milliseconds(200), outputGracePeriod: .milliseconds(200))
        let start = clock.now
        await #expect(throws: ProcessRunnerError.timedOut(.milliseconds(300))) {
            try await sh("trap '' TERM; sleep 10", timeout: .milliseconds(300), runner: runner)
        }
        #expect(clock.now - start < promptly)
    }

    @Test func timeoutAlsoStopsGrandchildren() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("feedini-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        await #expect(throws: ProcessRunnerError.timedOut(.milliseconds(300))) {
            try await sh("sleep 10 & echo $! > '\(pidFile.path)'; wait", timeout: .milliseconds(300))
        }
        let grandchild = try #require(
            pid_t(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        // The signal is sent, but the grandchild may take a moment to exit and be reaped.
        let deadline = clock.now + promptly
        while kill(grandchild, 0) == 0 && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(grandchild, 0) != 0, "the background sleep should have been killed with its parent")
    }

    @Test func doesNotWaitForGrandchildrenHoldingThePipe() async throws {
        // The background `sleep` inherits stdout and keeps it open after `sh` exits; its PID goes to stderr.
        let start = clock.now
        let output = try await sh("sleep 10 & echo $! >&2; printf done", timeout: .seconds(20))
        let elapsed = clock.now - start
        let grandchild = try #require(
            pid_t(String(decoding: output.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        kill(grandchild, SIGKILL)

        #expect(output.exitStatus == 0)
        #expect(output.stdout == Data("done".utf8))
        #expect(elapsed < promptly)
    }

    @Test func cancellationKillsTheProcess() async {
        let task = Task { try await sh("sleep 10", timeout: .seconds(20)) }
        try? await Task.sleep(for: .milliseconds(200))
        let start = clock.now
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(clock.now - start < promptly)
    }

    @Test func reportsLaunchFailures() async {
        await #expect {
            try await ProcessRunner().run(
                URL(fileURLWithPath: "/nonexistent/claude"), arguments: [], input: nil, timeout: .seconds(1))
        } throws: { error in
            if case ProcessRunnerError.launchFailed = error { true } else { false }
        }
    }
}
