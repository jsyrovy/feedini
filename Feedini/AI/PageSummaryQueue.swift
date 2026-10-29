import Foundation

/// Loads source pages (P) and summarizes them (T), only on the user's request, at most `maxParallel` at a time.
///
/// The page text is stored with the article, so T after P (or a second T after the summary language changed) doesn't
/// load the page again. A request for an article already being worked on is ignored, except that T makes a running
/// P go on to the summary. Nothing is retried by itself: it is the user's action, the error is shown in the detail.
/// The work and whether T asked for a summary are kept in `AIStatus.pages` only.
@MainActor
final class PageSummaryQueue {
    static let maxParallel = 2
    nonisolated static let notArticleMessage =
        "The page doesn't show the article (a cookie consent, a subscription or a login?). Open it with V, accept or "
        + "log in, then press T again."

    private unowned let host: any LibraryHost
    private let extractor: any PageExtracting
    private let caller: AICaller
    private let status: AIStatus
    private let configuration: @MainActor () -> AIConfiguration
    private let now: @Sendable () -> Date
    private var waiting: [Article.ID] = []
    private var tasks: [Article.ID: Task<Void, Never>] = [:]

    init(
        host: any LibraryHost, extractor: any PageExtracting, runner: any CommandRunning = ProcessRunner(),
        locator: ClaudeLocator = ClaudeLocator(), status: AIStatus,
        configuration: @escaping @MainActor () -> AIConfiguration, now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.host = host
        self.extractor = extractor
        caller = AICaller(host: host, runner: runner, locator: locator, status: status, now: now)
        self.status = status
        self.configuration = configuration
        self.now = now
    }

    /// P: loads the page's text unless it is stored.
    func loadPage(_ id: Article.ID) {
        guard let article = host.library.articles[id], article.pageText == nil else { return }
        enqueue(id, summary: false)
    }

    /// T: loads the page unless its text is stored, then summarizes it – unless `canSummarize` says no.
    func summarize(_ id: Article.ID) {
        guard configuration().isEnabled else {
            status.setPage(AIStatus.PageWork(phase: .failed(AIStatus.State.offMessage), summary: true), for: id)
            return
        }
        guard canSummarize(id) else { return }
        enqueue(id, summary: true)
    }

    /// Whether T does anything: not for a current summary, nor while one is being written (a failed one can be tried
    /// again).
    func canSummarize(_ id: Article.ID) -> Bool {
        guard let article = host.library.articles[id],
            !PageSummaryStep.isCurrent(article.pageSummary, language: configuration().languageCode)
        else { return false }
        guard let work = status.pages[id], work.summary else { return true }
        if case .failed = work.phase { return true }
        return false
    }

    /// The user opened the page in the window, where they may accept cookies or log in: the stored text is forgotten,
    /// so the next P / T loads the page again.
    func pageOpened(_ id: Article.ID) {
        guard host.library.articles[id]?.pageText != nil, tasks[id] == nil, !waiting.contains(id) else { return }
        host.update { $0.articles[id]?.pageText = nil }
    }

    var isRunning: Bool { !tasks.isEmpty || !waiting.isEmpty }

    /// Waits until nothing runs or waits (tests).
    func waitUntilIdle() async {
        while let task = tasks.values.first {
            await task.value
        }
    }

    private func enqueue(_ id: Article.ID, summary: Bool) {
        if tasks[id] != nil || waiting.contains(id) {
            if summary, let work = status.pages[id] {
                status.setPage(AIStatus.PageWork(phase: work.phase, summary: true), for: id)
            }
            return
        }
        let hasText = host.library.articles[id]?.pageText != nil
        status.setPage(AIStatus.PageWork(phase: hasText ? .summarizing : .loading, summary: summary), for: id)
        waiting.append(id)
        fill()
    }

    private func fill() {
        while tasks.count < Self.maxParallel, !waiting.isEmpty {
            let id = waiting.removeFirst()
            tasks[id] = Task {
                await self.process(id)
                self.tasks[id] = nil
                self.fill()
            }
        }
    }

    private func process(_ id: Article.ID) async {
        guard let article = host.library.articles[id] else {
            status.setPage(nil, for: id)
            return
        }
        if article.pageText == nil {
            guard await load(article) else { return }
        }
        guard status.pages[id]?.summary == true else {
            status.setPage(nil, for: id)
            return
        }
        await writeSummary(article.id)
    }

    /// Stores the page's text; returns whether it could be loaded.
    private func load(_ article: Article) async -> Bool {
        guard let link = article.link else {
            fail(article.id, "The article has no link to its page.")
            return false
        }
        let started = ContinuousClock.now
        do {
            let text = try await extractor.extract(link)
            host.update { $0.articles[article.id]?.pageText = text }
            let duration = String(describing: ContinuousClock.now - started)
            Log.feeds.info("Loaded a page: \(text.count) characters in \(duration, privacy: .public)")
            return true
        } catch {
            fail(article.id, error.message)
            Log.feeds.error("Loading a page failed: \(error.message, privacy: .public)")
            return false
        }
    }

    private func writeSummary(_ id: Article.ID) async {
        let configuration = configuration()
        guard configuration.isEnabled else {
            fail(id, AIStatus.State.offMessage)
            return
        }
        guard let article = host.library.articles[id],
            let request = PageSummaryStep.request(for: article, in: host.library, configuration: configuration)
        else {
            status.setPage(nil, for: id)
            return
        }
        status.setPage(AIStatus.PageWork(phase: .summarizing, summary: true), for: id)
        do {
            var outcome = PageSummaryStep.Outcome.empty
            let stats = try await caller.call(
                request, as: PageSummaryStep.Output.self, step: "Summarize page",
                claudePath: configuration.claudePath
            ) { [now] output, library in
                outcome = PageSummaryStep.apply(
                    output, to: id, language: configuration.languageCode, date: now(), in: &library)
            }
            Log.ai.info("Summarized a page in \(stats.durationMs) ms: \(String(describing: outcome), privacy: .public)")
            switch outcome {
            case .summarized: status.setPage(nil, for: id)
            case .notArticle: fail(id, Self.notArticleMessage)
            case .empty: fail(id, "claude gave an empty summary")
            }
        } catch {
            fail(id, error.message)
        }
    }

    private func fail(_ id: Article.ID, _ message: String) {
        status.setPage(AIStatus.PageWork(phase: .failed(message), summary: status.pages[id]?.summary ?? false), for: id)
    }
}
