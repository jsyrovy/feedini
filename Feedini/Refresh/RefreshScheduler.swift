/// Refreshes periodically, on the main actor.
///
/// Refreshes never overlap: the next one starts `interval` after the previous one finished. `refreshNow()` cuts the
/// wait short; while a refresh runs it does nothing (its result is about to arrive). The refresh itself does its work
/// off the main actor.
@MainActor
final class RefreshScheduler {
    private(set) var interval: Duration
    private let refresh: @MainActor () async -> Void
    private let sleep: @Sendable (Duration) async throws -> Void
    /// The latest loop; once cancelled, it may still be finishing its refresh.
    private var loop: Task<Void, Never>?
    /// Whether the loop waits between two refreshes.
    private var isSleeping = false

    init(
        interval: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        refresh: @escaping @MainActor () async -> Void
    ) {
        self.interval = interval
        self.sleep = sleep
        self.refresh = refresh
    }

    /// Starts with a refresh right away. Does nothing if already running.
    func start() {
        run(refreshingFirst: true)
    }

    /// Refreshes right away if waiting between refreshes.
    func refreshNow() {
        guard isSleeping, loop?.isCancelled == false else { return }
        loop?.cancel()
        run(refreshingFirst: true)
    }

    /// A new interval applies to the current wait at once: it starts again with the new length.
    func setInterval(_ interval: Duration) {
        guard interval != self.interval else { return }
        self.interval = interval
        guard isSleeping, loop?.isCancelled == false else { return }
        loop?.cancel()
        run(refreshingFirst: false)
    }

    /// Stops and waits for the loop to end.
    func stop() async {
        loop?.cancel()
        await loop?.value
    }

    private func run(refreshingFirst: Bool) {
        guard loop?.isCancelled != false else { return }
        loop = Task { [weak self, previous = loop] in
            // A cancelled loop may still be ending; two loops never run at once.
            await previous?.value
            var refreshes = refreshingFirst
            while !Task.isCancelled {
                guard let self else { return }
                if refreshes {
                    await self.refresh()
                }
                refreshes = true
                guard !Task.isCancelled else { return }
                self.isSleeping = true
                try? await self.sleep(self.interval)
                self.isSleeping = false
            }
        }
    }
}
