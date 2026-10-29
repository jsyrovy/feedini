import Synchronization

/// An event that happens at most once and can be awaited from any task.
final class OneShotSignal: Sendable {
    private struct State {
        var hasFired = false
        var nextWaiterID = 0
        var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
        /// Waiters cancelled before their continuation was registered.
        var cancelledWaiterIDs: Set<Int> = []
    }

    private let state = Mutex(State())

    var hasFired: Bool {
        state.withLock { $0.hasFired }
    }

    func fire() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            guard !state.hasFired else { return [] }
            state.hasFired = true
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Returns once the signal has fired, or as soon as the calling task is cancelled.
    func wait() async {
        let id = state.withLock { state in
            state.nextWaiterID += 1
            return state.nextWaiterID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeNow = state.withLock { state in
                    if state.hasFired || state.cancelledWaiterIDs.remove(id) != nil {
                        return true
                    }
                    state.waiters[id] = continuation
                    return false
                }
                if resumeNow {
                    continuation.resume()
                }
            }
        } onCancel: {
            let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
                if let waiter = state.waiters.removeValue(forKey: id) {
                    return waiter
                }
                state.cancelledWaiterIDs.insert(id)
                return nil
            }
            waiter?.resume()
        }
    }

    /// Returns once the signal has fired or `timeout` has elapsed, whichever comes first.
    func wait(timeout: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.wait() }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }
}
