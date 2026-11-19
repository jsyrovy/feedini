import Foundation
import Synchronization
import Testing

@testable import Feedini

@MainActor
struct UpdateCheckerTests {
    private static let current = AppVersion("0.3")!

    private static func release(_ version: String) -> LatestRelease {
        LatestRelease(
            version: AppVersion(version)!,
            pageURL: URL(string: "https://github.com/jsyrovy/feedini/releases/tag/v\(version)")!)
    }

    private let sleeper = ManualSleeper()

    private func checker(
        _ fetch: ScriptedRelease, currentVersion: AppVersion? = Self.current
    ) -> UpdateChecker {
        UpdateChecker(currentVersion: currentVersion, fetch: fetch.callAsFunction, sleep: sleeper.sleep(for:))
    }

    @Test func newerReleaseIsAvailable() async {
        let checker = checker(ScriptedRelease([.success(Self.release("0.10"))]))
        #expect(checker.state == .unchecked)
        #expect(checker.available == nil)

        await checker.checkNow()

        #expect(checker.state == .available(Self.release("0.10")))
        #expect(checker.available == Self.release("0.10"))
    }

    @Test(arguments: ["0.3", "0.2"])
    func sameOrOlderReleaseIsUpToDate(version: String) async {
        let checker = checker(ScriptedRelease([.success(Self.release(version))]))

        await checker.checkNow()

        #expect(checker.state == .upToDate(Self.current))
        #expect(checker.available == nil)
    }

    @Test func anyReleaseIsAvailableWithoutAVersionOfOurOwn() async {
        let checker = checker(ScriptedRelease([.success(Self.release("0.3"))]), currentVersion: nil)

        await checker.checkNow()

        #expect(checker.state == .available(Self.release("0.3")))
    }

    @Test func failureIsReportedAndTheNextCheckReplacesIt() async {
        let checker = checker(ScriptedRelease([.failure(.status(429)), .success(Self.release("0.3"))]))

        await checker.checkNow()
        #expect(checker.state == .failed("GitHub answered with HTTP 429"))

        await checker.checkNow()
        #expect(checker.state == .upToDate(Self.current))
    }

    @Test func checkWhileOneRunsDoesNothing() async {
        let fetch = ScriptedRelease([])
        let checker = checker(fetch)
        var calls = fetch.calls.makeAsyncIterator()
        let running = Task { await checker.checkNow() }
        await calls.next()
        #expect(checker.state == .checking)

        await checker.checkNow()

        #expect(fetch.count == 1)
        // A cancelled check leaves what was known before it.
        running.cancel()
        await running.value
        #expect(checker.state == .unchecked)
    }

    @Test func dailyChecksRightAwayAndThenEveryDay() async {
        let fetch = ScriptedRelease([.success(Self.release("0.3")), .success(Self.release("0.4"))])
        let checker = checker(fetch)
        var sleeps = sleeper.sleeps.makeAsyncIterator()

        checker.setDaily(true)

        #expect(await sleeps.next() == UpdateChecker.interval)
        #expect(checker.state == .upToDate(Self.current))
        sleeper.wake()
        #expect(await sleeps.next() == UpdateChecker.interval)
        #expect(checker.state == .available(Self.release("0.4")))
        #expect(fetch.count == 2)
        checker.setDaily(false)
    }

    @Test func startingTwiceRunsOneLoop() async {
        let fetch = ScriptedRelease([.success(Self.release("0.3"))])
        let checker = checker(fetch)
        var sleeps = sleeper.sleeps.makeAsyncIterator()

        checker.setDaily(true)
        checker.setDaily(true)

        _ = await sleeps.next()
        #expect(fetch.count == 1)
        checker.setDaily(false)
    }

    @Test func stoppingEndsTheSleepAndStartingAgainChecksAtOnce() async {
        let fetch = ScriptedRelease([.success(Self.release("0.3")), .success(Self.release("0.4"))])
        let checker = checker(fetch)
        var sleeps = sleeper.sleeps.makeAsyncIterator()
        checker.setDaily(true)
        _ = await sleeps.next()

        checker.setDaily(false)
        checker.setDaily(true)

        // The stopped loop didn't check again: the new one made the second check. ManualSleeper would stop the test
        // if both slept at once.
        _ = await sleeps.next()
        #expect(fetch.count == 2)
        #expect(checker.state == .available(Self.release("0.4")))
        checker.setDaily(false)
    }

    @Test func stoppingDuringACheckDoesNotSkipTheNextOne() async {
        let fetch = ScriptedRelease([])
        let checker = checker(fetch)
        var calls = fetch.calls.makeAsyncIterator()
        checker.setDaily(true)
        await calls.next()

        checker.setDaily(false)
        checker.setDaily(true)

        // The new loop waited for the cancelled check instead of finding one still running.
        await calls.next()
        #expect(fetch.count == 2)
        #expect(checker.state == .checking)
        checker.setDaily(false)
    }
}

/// Answers checks with the given results in order; after the last one, a check runs until it is cancelled.
private final class ScriptedRelease: Sendable {
    /// Reports every check when it starts.
    let calls: AsyncStream<Void>
    private let callsContinuation: AsyncStream<Void>.Continuation
    private let state: Mutex<(count: Int, results: [Result<LatestRelease, UpdateError>])>

    init(_ results: [Result<LatestRelease, UpdateError>]) {
        (calls, callsContinuation) = AsyncStream.makeStream(of: Void.self)
        state = Mutex((0, results))
    }

    var count: Int {
        state.withLock { $0.count }
    }

    @Sendable func callAsFunction() async throws -> LatestRelease {
        let result = state.withLock { state in
            state.count += 1
            return state.results.isEmpty ? nil : state.results.removeFirst()
        }
        callsContinuation.yield()
        if let result {
            return try result.get()
        }
        await OneShotSignal().wait()
        throw CancellationError()
    }
}
