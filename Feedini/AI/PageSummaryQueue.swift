import Foundation

/// Loads source pages (P) and summarizes them (T, Shift+S), only on the user's request, at most `maxParallel` at a
/// time.
///
/// The page text is stored (`LibraryHost.storePageText`), so T after P (or a second T after the summary language changed) doesn't
/// load the page again. A request for an article already being worked on is ignored, except that T makes a running
/// P go on to the summary. Nothing is retried by itself: it is the user's action, the error is shown in the detail.
/// The work and whether T asked for a summary are kept in `AIStatus.pages` only.
///
/// A saved link (`SavedLink`) has no feed text, so its page text is all it has: P loads it again instead (`reload`),
/// keeping the stored one until the new one is there, opening the page (V) doesn't forget it, and neither does
/// `not_article`. Loading it fills in the title, source and date from the page.
@MainActor
final class PageSummaryQueue {
    static let maxParallel = 2
    private nonisolated static let notArticle =
        "The page doesn't show the article (a cookie consent, a subscription or a login?). Open it with V, accept or "
        + "log in, then press"
    nonisolated static let notArticleMessage = notArticle + " T again."
    /// A saved link keeps its text, so T alone would summarize the same text again.
    nonisolated static let notArticleLinkMessage = notArticle + " P to load it again."

    private unowned let host: any LibraryHost
    private let extractor: any PageExtracting
    private let caller: AICaller
    private let status: AIStatus
    private let configuration: @MainActor () -> AIConfiguration
    private let now: @Sendable () -> Date
    private var waiting: [Article.ID] = []
    private var tasks: [Article.ID: Task<Void, Never>] = [:]
    /// Saved links whose page is loaded again even though its text is stored (`reload`).
    private var reloading: Set<Article.ID> = []

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
        guard host.library.articles[id] != nil, !host.library.pageTextIDs.contains(id) else { return }
        enqueue(id, summary: false)
    }

    /// T: loads the page unless its text is stored, then summarizes it – unless `canSummarize` says no.
    func summarize(_ id: Article.ID) {
        guard configuration().isEnabled else {
            status.setPage(AIStatus.PageWork(phase: .failed(AIStatus.State.offMessage), summary: true), for: id)
            return
        }
        prepare(id)
    }

    /// Shift+S: like T, but also when AI is off – then the page is still loaded and stored for later, and the summary
    /// fails with the reason (the user isn't looking at the article, the error waits in its row).
    func prepare(_ id: Article.ID) {
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
        return !work.isRunning
    }

    /// The user opened the page in the window, where they may accept cookies or log in: the stored text is forgotten,
    /// so the next P / T loads the page again. A saved link keeps it (`Library.forgetPageText`); P loads it again.
    func pageOpened(_ id: Article.ID) {
        guard host.library.pageTextIDs.contains(id), tasks[id] == nil, !waiting.contains(id) else { return }
        host.update { $0.forgetPageText(id) }
    }

    /// P on a saved link: loads its page again – after the user accepted cookies or logged in with V – and with AI on
    /// writes a new summary of it. The stored text stays until the new one is stored, also when loading fails.
    func reload(_ id: Article.ID) {
        guard host.library.articles[id] != nil, tasks[id] == nil, !waiting.contains(id) else { return }
        reloading.insert(id)
        enqueue(id, summary: configuration().isEnabled)
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
        let loads = reloading.contains(id) || !host.library.pageTextIDs.contains(id)
        status.setPage(AIStatus.PageWork(phase: loads ? .loading : .summarizing, summary: summary), for: id)
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
        let reloads = reloading.remove(id) != nil
        guard let article = host.library.articles[id] else {
            status.setPage(nil, for: id)
            return
        }
        var text = reloads ? nil : await host.pageText(id)
        if text == nil {
            text = await load(article)
        }
        guard let text else { return }
        guard status.pages[id]?.summary == true else {
            status.setPage(nil, for: id)
            return
        }
        await writeSummary(article.id, text: text)
    }

    /// Loads and stores the page's text; `nil` when it couldn't be loaded.
    private func load(_ article: Article) async -> String? {
        guard let link = article.link else {
            fail(article.id, "The article has no link to its page.")
            return nil
        }
        let summary = status.pages[article.id]?.summary ?? false
        status.setPage(AIStatus.PageWork(phase: .loading, summary: summary), for: article.id)
        let started = ContinuousClock.now
        let content: PageContent
        do {
            content = try await extractor.extract(link)
        } catch {
            fail(article.id, error.message)
            Log.feeds.error("Loading a page failed: \(error.message, privacy: .public)")
            return nil
        }
        let text = content.text
        do {
            try await host.storePageText(text, for: article.id)
        } catch {
            fail(article.id, "The page text couldn't be stored: \(error.localizedDescription)")
            Log.store.error("Storing a page text failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        host.update { $0.applyPageMetadata(content.metadata, to: article.id) }
        let duration = String(describing: ContinuousClock.now - started)
        Log.feeds.info("Loaded a page: \(text.count) characters in \(duration, privacy: .public)")
        return text
    }

    private func writeSummary(_ id: Article.ID, text: String) async {
        let configuration = configuration()
        guard configuration.isEnabled else {
            fail(id, AIStatus.State.offMessage)
            return
        }
        guard let article = host.library.articles[id] else {
            status.setPage(nil, for: id)
            return
        }
        let request = PageSummaryStep.request(
            for: article, pageText: text, in: host.library, configuration: configuration)
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
            case .notArticle: fail(id, article.isSavedLink ? Self.notArticleLinkMessage : Self.notArticleMessage)
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
