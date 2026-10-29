import Synchronization

@testable import Feedini

/// A sleep function for timer-driven loops in tests: every call is reported on `sleeps` and suspends until `wake()`.
///
/// A loop that reported a sleep has finished everything it does before sleeping, so a test can await
/// `sleeps.next()`, check the state, and `wake()` the loop for its next step – no real time passes.
/// A cancelled sleep throws `CancellationError`, like `Task.sleep`.
final class ManualSleeper: Sendable {
    let sleeps: AsyncStream<Duration>

    private let sleepsContinuation: AsyncStream<Duration>.Continuation
    private let current = Mutex<OneShotSignal?>(nil)

    init() {
        (sleeps, sleepsContinuation) = AsyncStream.makeStream(of: Duration.self)
    }

    func sleep(for duration: Duration) async throws {
        let signal = OneShotSignal()
        current.withLock { current in
            precondition(current == nil, "ManualSleeper supports one sleeping task at a time")
            current = signal
        }
        sleepsContinuation.yield(duration)
        await signal.wait()
        current.withLock { current in
            if current === signal {
                current = nil
            }
        }
        guard signal.hasFired else { throw CancellationError() }
    }

    /// Ends the current sleep.
    func wake() {
        let signal = current.withLock { current in
            defer { current = nil }
            return current
        }
        precondition(signal != nil, "wake() called while nothing sleeps")
        signal?.fire()
    }
}
