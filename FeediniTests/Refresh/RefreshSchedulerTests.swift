import Testing

@testable import Feedini

@MainActor
struct RefreshSchedulerTests {
    private let sleeper = ManualSleeper()
    private let counter = Counter()

    @MainActor
    final class Counter {
        var refreshes = 0
    }

    private func scheduler(_ minutes: Int = 15) -> RefreshScheduler {
        RefreshScheduler(interval: .seconds(minutes * 60), sleep: sleeper.sleep(for:)) { [counter] in
            counter.refreshes += 1
        }
    }

    @Test func refreshesRightAwayAndThenEveryInterval() async {
        let scheduler = scheduler()
        var sleeps = sleeper.sleeps.makeAsyncIterator()

        scheduler.start()
        #expect(await sleeps.next() == .seconds(900))
        #expect(counter.refreshes == 1)
        sleeper.wake()
        #expect(await sleeps.next() == .seconds(900))
        #expect(counter.refreshes == 2)
        // Starting again while running does nothing.
        scheduler.start()
        await scheduler.stop()

        #expect(counter.refreshes == 2)
    }

    @Test func refreshNowCutsTheWaitShort() async {
        let scheduler = scheduler()
        var sleeps = sleeper.sleeps.makeAsyncIterator()

        scheduler.start()
        _ = await sleeps.next()
        scheduler.refreshNow()
        #expect(await sleeps.next() == .seconds(900))
        await scheduler.stop()

        #expect(counter.refreshes == 2)
    }

    @Test func refreshNowDoesNothingWhileARefreshRunsOrWhenStopped() async {
        let gate = OneShotSignal()
        let entered = OneShotSignal()
        let scheduler = RefreshScheduler(interval: .seconds(60), sleep: sleeper.sleep(for:)) { [counter] in
            counter.refreshes += 1
            entered.fire()
            await gate.wait()
        }
        var sleeps = sleeper.sleeps.makeAsyncIterator()

        scheduler.refreshNow()
        scheduler.start()
        await entered.wait()
        scheduler.refreshNow()
        gate.fire()
        _ = await sleeps.next()
        await scheduler.stop()

        #expect(counter.refreshes == 1)
    }

    @Test func aNewIntervalRestartsTheWaitWithoutRefreshing() async {
        let scheduler = scheduler(15)
        var sleeps = sleeper.sleeps.makeAsyncIterator()

        scheduler.start()
        _ = await sleeps.next()
        scheduler.setInterval(.seconds(300))
        #expect(await sleeps.next() == .seconds(300))
        #expect(counter.refreshes == 1)
        // The same interval again changes nothing.
        scheduler.setInterval(.seconds(300))
        sleeper.wake()
        #expect(await sleeps.next() == .seconds(300))
        await scheduler.stop()

        #expect(counter.refreshes == 2)
        #expect(scheduler.interval == .seconds(300))
    }

    @Test func aNewIntervalBeforeStartIsUsedByTheFirstWait() async {
        let scheduler = scheduler(15)
        var sleeps = sleeper.sleeps.makeAsyncIterator()

        scheduler.setInterval(.seconds(3600))
        scheduler.start()
        #expect(await sleeps.next() == .seconds(3600))
        await scheduler.stop()
    }
}
