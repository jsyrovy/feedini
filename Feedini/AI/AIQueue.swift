import Foundation

/// Owns the library on the main actor; the AI queues read it and change it through it.
@MainActor
protocol LibraryHost: AnyObject {
    var library: Library { get }
    func update(_ change: (inout Library) -> Void)
    /// The stored text of the article's source page (`Library.pageTextIDs`); `nil` when there is none or it can't be
    /// read anymore (then it is forgotten).
    func pageText(_ id: Article.ID) async -> String?
    /// Stores the text of the article's source page and lists it in `Library.pageTextIDs`.
    func storePageText(_ text: String, for id: Article.ID) async throws
}

/// AI settings as the queues use them.
struct AIConfiguration: Sendable, Equatable {
    static let defaultModel = "claude-haiku-5-5"
    static let defaultEffort = "low"
    static let defaultSingleArticleSummaries = SingleArticleSummaries.never

    var isEnabled = true
    var assignModel = defaultModel
    var summaryModel = defaultModel
    var effort = defaultEffort
    /// The code of the output language (`cs`).
    var languageCode = "en"
    /// The English name of the output language ("Czech").
    var language: String { OutputLanguage.name(of: languageCode) }
    /// A path to `claude` set in Settings; empty to look it up.
    var claudePath = ""
    var singleArticleSummaries = defaultSingleArticleSummaries
}

/// Makes the AI calls of both queues: finds claude, runs the call, applies the answer to the library, and records
/// the call in the status, the usage statistics and the log. Usage is counted whenever claude actually ran (also
/// when the answer was an error), not when it couldn't be found or started.
@MainActor
struct AICaller {
    unowned let host: any LibraryHost
    let runner: any CommandRunning
    let locator: ClaudeLocator
    let status: AIStatus
    let now: @Sendable () -> Date

    /// Returns the call's stats; throws (after recording) when the call failed.
    @discardableResult
    func call<Output: Decodable & Sendable>(
        _ request: ClaudeRequest, as type: Output.Type, step: String, claudePath: String,
        apply: (Output, inout Library) -> Void
    ) async throws(ClaudeError) -> ClaudeCallStats {
        let client = ClaudeClient(runner: runner) { [locator] in locator.locate(customPath: claudePath) }
        do {
            let (output, stats) = try await client.run(request, as: type)
            status.record(AIStatus.Call(date: now(), step: step, stats: stats))
            host.update { library in
                apply(output, &library)
                library.recordAICall(at: now(), stats: stats)
            }
            return stats
        } catch {
            status.record(AIStatus.Call(date: now(), step: step, error: error.message))
            if error.isTransient {
                host.update { $0.recordAICall(at: now(), stats: nil) }
            }
            Log.ai.error("\(step, privacy: .public) failed: \(error.message, privacy: .public)")
            throw error
        }
    }
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
    private let caller: AICaller
    private let status: AIStatus
    private let configuration: @MainActor () -> AIConfiguration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date
    private var run: Task<Void, Never>?
    /// Articles whose batch failed `maxAttempts` times; skipped until `trigger(retryingFailed: true)`.
    private var deferred = Set<Article.ID>()
    /// Why the last call failed, shown while deferred articles wait.
    private var lastError: String?

    /// Called after every applied batch (stories changed, so summaries may be needed).
    var onBatchApplied: (@MainActor () -> Void)?

    init(
        host: any LibraryHost, runner: any CommandRunning = ProcessRunner(), locator: ClaudeLocator = ClaudeLocator(),
        status: AIStatus,
        configuration: @escaping @MainActor () -> AIConfiguration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.host = host
        caller = AICaller(host: host, runner: runner, locator: locator, status: status, now: now)
        self.status = status
        self.configuration = configuration
        self.sleep = sleep
        self.now = now
    }

    /// Articles waiting for the assign step, newest first.
    nonisolated static func pending(
        in library: Library, excluding deferred: Set<Article.ID> = [], now: Date
    ) -> [Article.ID] {
        let assigned = library.storyIDsByArticle()
        let cutoff = now.addingTimeInterval(-Retention.attachWindow)
        return library.articles.values
            .filter { article in
                assigned[article.id] == nil && !article.isSavedLink && !deferred.contains(article.id)
                    && (!article.isRead || article.date >= cutoff)
            }
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
            let request = ClaudeRequest(
                model: configuration.assignModel, effort: configuration.effort, systemPrompt: Prompts.assign,
                schema: Prompts.assignSchema, payload: input)
            do {
                var metrics = AssignValidation.Metrics()
                let stats = try await caller.call(
                    request, as: AssignStep.Output.self, step: "Organize \(batch.count)",
                    claudePath: configuration.claudePath
                ) { output, library in
                    metrics = AssignValidation.apply(
                        output, map: map, language: configuration.languageCode, to: &library)
                }
                Log.ai.info(
                    """
                    Assigned \(batch.count) articles in \(stats.durationMs) ms ($\(stats.costUSD)): \
                    attached \(metrics.attached), new stories \(metrics.newStories), new topics \(metrics.newTopics), \
                    missing \(metrics.missing), unknown IDs \(metrics.unknownIDs), \
                    unresolved topics \(metrics.unresolvedTopics)
                    """)
                onBatchApplied?()
                isFirst = false
                failures = 0
                lastError = nil
            } catch {
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

/// Writes summaries of unread (or saved) stories that need one, up to `maxParallel` calls at a time, in the order of
/// `SummaryStep.pending` (stories from several feeds first, newer first). Like the assign queue it derives the work
/// from the library, so a story that gets a new article, or a change of the summary language, simply makes stories
/// pending again. Topics in another language are translated alongside, in one call.
///
/// A failing batch is retried after a delay; a story that failed `maxAttempts` times waits for the next refresh.
@MainActor
final class SummaryQueue {
    static let maxParallel = 3
    static let maxAttempts = 3
    static let retryDelay: Duration = .seconds(30)

    private unowned let host: any LibraryHost
    private let caller: AICaller
    private let status: AIStatus
    private let configuration: @MainActor () -> AIConfiguration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var inFlight = Set<Story.ID>()
    private var failures: [Story.ID: Int] = [:]
    private var isTranslating = false
    /// Set by a setup error (no claude); cleared by the next trigger.
    private var isBlocked = false

    init(
        host: any LibraryHost, runner: any CommandRunning = ProcessRunner(), locator: ClaudeLocator = ClaudeLocator(),
        status: AIStatus, configuration: @escaping @MainActor () -> AIConfiguration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.host = host
        caller = AICaller(host: host, runner: runner, locator: locator, status: status, now: now)
        self.status = status
        self.configuration = configuration
        self.sleep = sleep
    }

    var isRunning: Bool { !tasks.isEmpty }

    func trigger(retryingFailed: Bool = false) {
        if retryingFailed {
            failures = [:]
            status.clearSummaryErrors()
        }
        isBlocked = false
        fill()
    }

    /// Waits until no call runs (tests).
    func waitUntilIdle() async {
        while let task = tasks.values.first {
            await task.value
        }
    }

    func cancel() {
        for task in tasks.values {
            task.cancel()
        }
    }

    private var deferred: Set<Story.ID> {
        Set(failures.filter { $0.value >= Self.maxAttempts }.keys)
    }

    private func fill() {
        let configuration = configuration()
        guard configuration.isEnabled, !isBlocked else {
            status.setSummarizing(inFlight)
            return
        }
        if !isTranslating {
            let topics = TopicTranslation.pending(in: host.library, language: configuration.languageCode)
            if !topics.isEmpty {
                isTranslating = true
                launch { await self.translate(topics, configuration) }
            }
        }
        var pending = SummaryStep.pending(
            in: host.library, language: configuration.languageCode,
            singleArticles: configuration.singleArticleSummaries, excluding: inFlight.union(deferred)
        )[...]
        while tasks.count < Self.maxParallel, !pending.isEmpty {
            let batch = Array(pending.prefix(SummaryStep.batchSize))
            pending = pending.dropFirst(batch.count)
            inFlight.formUnion(batch)
            launch { await self.summarize(batch, configuration) }
        }
        status.setSummarizing(inFlight)
    }

    private func launch(_ work: @escaping @MainActor () async -> Void) {
        let id = UUID()
        tasks[id] = Task {
            await work()
            self.tasks[id] = nil
            if !Task.isCancelled {
                self.fill()
            }
        }
    }

    private func summarize(_ batch: [Story.ID], _ configuration: AIConfiguration) async {
        defer { inFlight.subtract(batch) }
        let (input, map) = SummaryStep.payload(for: batch, in: host.library, languageName: configuration.language)
        let request = ClaudeRequest(
            model: configuration.summaryModel, effort: configuration.effort, systemPrompt: Prompts.summary,
            schema: Prompts.summarySchema, payload: input)
        do {
            var written = Set<Story.ID>()
            let stats = try await caller.call(
                request, as: SummaryStep.Output.self, step: "Summarize \(batch.count)",
                claudePath: configuration.claudePath
            ) { output, library in
                written = SummaryStep.apply(output, map: map, language: configuration.languageCode, to: &library)
            }
            for id in batch where !written.contains(id) {
                failures[id, default: 0] += 1
            }
            Log.ai.info("Summarized \(written.count) of \(batch.count) stories in \(stats.durationMs) ms")
        } catch {
            guard error.isTransient else {
                block(error)
                return
            }
            for id in batch {
                failures[id, default: 0] += 1
                if failures[id, default: 0] >= Self.maxAttempts {
                    status.setSummaryError(error.message, for: id)
                }
            }
            try? await sleep(Self.retryDelay)
        }
    }

    private func translate(_ topics: [Topic.ID], _ configuration: AIConfiguration) async {
        defer { isTranslating = false }
        let (payload, map) = TopicTranslation.payload(
            for: topics, in: host.library, languageName: configuration.language)
        let request = ClaudeRequest(
            model: configuration.assignModel, effort: configuration.effort, systemPrompt: Prompts.translateTopics,
            schema: Prompts.translateTopicsSchema, payload: payload)
        do {
            try await caller.call(
                request, as: TopicTranslation.Payload.self, step: "Translate topics",
                claudePath: configuration.claudePath
            ) { output, library in
                TopicTranslation.apply(output, map: map, language: configuration.languageCode, to: &library)
            }
        } catch {
            if error.isTransient {
                try? await sleep(Self.retryDelay)
            } else {
                block(error)
            }
        }
    }

    /// A setup error (no claude): nothing more until the next trigger.
    private func block(_ error: ClaudeError) {
        isBlocked = true
        status.set(.unavailable(error.message))
    }
}
