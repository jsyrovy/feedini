import Foundation

/// Owns the library on the main actor; the AI queues read it and change it through it.
@MainActor
protocol LibraryHost: AnyObject {
    var library: Library { get }
    func update(_ change: (inout Library) -> Void)
}

/// AI settings as the queues use them.
struct AIConfiguration: Sendable, Equatable {
    var isEnabled = true
    var assignModel = "claude-haiku-5-5"
    var summaryModel = "claude-haiku-5-5"
    var effort = "low"
    /// The English name of the output language ("Czech").
    var language = "English"
    /// A path to `claude` set in Settings; empty to look it up.
    var claudePath = ""
}

/// Organizes new articles into stories, one batch at a time.
///
/// The work is derived from the library: every article without a story is pending (unread ones, and read ones
/// still in the attach window), so nothing is lost across restarts. Batches go newest first; the first batch of a
/// run is small (`firstBatchSize`) so the first stories show up quickly, later ones take `batchSize`. Each batch
/// builds on the stories of the previous one, so batches never run in parallel. A failing call is retried with a
/// backoff; after `maxAttempts` its articles wait for the next refresh. A setup problem (no claude) stops the run.
@MainActor
final class AssignQueue {
    static let firstBatchSize = 10
    static let batchSize = 20
    static let maxAttempts = 3
    static let retryDelays: [Duration] = [.seconds(10), .seconds(60)]

    private unowned let host: any LibraryHost
    private let runner: any CommandRunning
    private let locator: ClaudeLocator
    private let status: AIStatus
    private let configuration: @MainActor () -> AIConfiguration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date
    private var run: Task<Void, Never>?
    /// Articles whose batch failed `maxAttempts` times; skipped until `trigger(retryingFailed: true)`.
    private var deferred = Set<Article.ID>()

    /// Called with the stories that got articles (for their summaries).
    var onStoriesChanged: (@MainActor ([Story.ID]) -> Void)?

    init(
        host: any LibraryHost, runner: any CommandRunning = ProcessRunner(), locator: ClaudeLocator = ClaudeLocator(),
        status: AIStatus,
        configuration: @escaping @MainActor () -> AIConfiguration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.host = host
        self.runner = runner
        self.locator = locator
        self.status = status
        self.configuration = configuration
        self.sleep = sleep
        self.now = now
    }

    /// Articles waiting for the assign step, newest first.
    static func pending(in library: Library, excluding deferred: Set<Article.ID> = [], now: Date) -> [Article.ID] {
        let assigned = library.storyIDsByArticle()
        let cutoff = now.addingTimeInterval(-Retention.attachWindow)
        return library.articles.values
            .filter { assigned[$0.id] == nil && !deferred.contains($0.id) && (!$0.isRead || $0.date >= cutoff) }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }
            .map(\.id)
    }

    var isRunning: Bool { run != nil }

    /// Starts working through the pending articles unless already running (a running queue picks up new ones by
    /// itself). After a refresh or a settings change, `retryingFailed` gives deferred articles another chance.
    func trigger(retryingFailed: Bool = false) {
        if retryingFailed {
            deferred = []
        }
        guard run == nil else { return }
        run = Task { [weak self] in
            await self?.work()
            self?.run = nil
        }
    }

    /// Waits for the current run to end (tests).
    func waitUntilIdle() async {
        await run?.value
    }

    /// Stops after the running call; a backoff wait ends at once.
    func cancel() {
        run?.cancel()
    }

    private func work() async {
        var isFirst = true
        var failures = 0
        var lastError: String?
        while !Task.isCancelled {
            let configuration = configuration()
            guard configuration.isEnabled else {
                status.set(.off)
                return
            }
            let pending = Self.pending(in: host.library, excluding: deferred, now: now())
            guard !pending.isEmpty else {
                status.set(deferred.isEmpty ? .idle : .unavailable(lastError ?? "organizing failed"))
                return
            }
            status.set(.organizing(pending.count))
            let batch = Array(pending.prefix(isFirst ? Self.firstBatchSize : Self.batchSize))
            let (input, map) = AssignStep.payload(
                for: batch, in: host.library, language: configuration.language, now: now())
            let request = AssignStep.request(input, model: configuration.assignModel, effort: configuration.effort)
            let client = ClaudeClient(runner: runner) { [locator, path = configuration.claudePath] in
                locator.locate(customPath: path)
            }
            do {
                let (output, stats) = try await client.run(request, as: AssignStep.Output.self)
                status.record(AIStatus.Call(date: now(), step: "Organize \(batch.count)", stats: stats))
                var result = AssignValidation.Result()
                host.update { result = AssignValidation.apply(output, map: map, to: &$0) }
                let metrics = result.metrics
                Log.ai.info(
                    """
                    Assigned \(batch.count) articles in \(stats.durationMs) ms ($\(stats.costUSD)): \
                    attached \(metrics.attached), new stories \(metrics.newStories), new topics \(metrics.newTopics), \
                    missing \(metrics.missing), unknown IDs \(metrics.unknownIDs), \
                    unresolved topics \(metrics.unresolvedTopics)
                    """)
                onStoriesChanged?(result.changedStories)
                isFirst = false
                failures = 0
            } catch {
                status.record(AIStatus.Call(date: now(), step: "Organize \(batch.count)", error: error.message))
                Log.ai.error("Assign failed: \(error.message, privacy: .public)")
                guard error.isTransient else {
                    status.set(.unavailable(error.message))
                    return
                }
                lastError = error.message
                failures += 1
                if failures >= Self.maxAttempts {
                    deferred.formUnion(batch)
                    failures = 0
                    continue
                }
                do {
                    try await sleep(Self.retryDelays[min(failures, Self.retryDelays.count) - 1])
                } catch {
                    return
                }
            }
        }
    }
}
