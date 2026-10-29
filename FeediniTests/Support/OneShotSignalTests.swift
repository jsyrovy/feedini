import Testing

@testable import Feedini

struct OneShotSignalTests {
    @Test func fireWakesEveryWaiter() async {
        let signal = OneShotSignal()
        let first = Task { await signal.wait() }
        let second = Task { await signal.wait() }

        signal.fire()
        await first.value
        await second.value

        #expect(signal.hasFired)
    }

    @Test func waitAfterFireReturnsImmediately() async {
        let signal = OneShotSignal()
        signal.fire()
        signal.fire()
        await signal.wait()
        #expect(signal.hasFired)
    }

    @Test func waitInACancelledTaskReturnsWithoutFire() async {
        let signal = OneShotSignal()
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await signal.wait()
        }
        await waiter.value
        #expect(!signal.hasFired)
    }

    @Test func timeoutEndsTheWaitWithoutFire() async {
        let signal = OneShotSignal()
        let clock = ContinuousClock()
        let start = clock.now

        await signal.wait(timeout: .milliseconds(50))

        #expect(clock.now - start >= .milliseconds(50))
        #expect(!signal.hasFired)
    }

    @Test func fireEndsAWaitWithTimeoutEarly() async {
        let signal = OneShotSignal()
        let clock = ContinuousClock()
        let start = clock.now

        signal.fire()
        await signal.wait(timeout: .seconds(10))

        #expect(clock.now - start < .seconds(5))
    }
}
