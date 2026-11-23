import Foundation

/// Summarizes source pages (T, Shift+S), only on the user's request, on top of the `PageLoader`: it loads the page
/// unless its text is stored and then calls back (`PageSummarizing`), in the same slot of at most
/// `PageLoader.maxParallel`. The work and whether T asked for a summary are kept in `PageStatus`.
///
/// A saved link keeps its text when the answer is `not_article` (P loads it again), and P on it (`reload`) writes a
/// new summary when AI is on.
@MainActor
final class PageSummaryQueue: PageSummarizing {
    private nonisolated static let notArticle =
        "The page doesn't show the article (a cookie consent, a subscription or a login?). Open it with V, accept or "
        + "log in, then press"
    nonisolated static let notArticleMessage = notArticle + " T again."
    /// A saved link keeps its text, so T alone would summarize the same text again.
    nonisolated static let notArticleLinkMessage = notArticle + " P to load it again."

    let loader: PageLoader
    private unowned let host: any LibraryHost
    private let caller: AICaller
    private let configuration: @MainActor () -> AIConfiguration
    private let now: @Sendable () -> Date
    private var status: PageStatus { loader.status }

    init(
        host: any LibraryHost, loader: PageLoader, runner: any CommandRunning = ProcessRunner(),
        locator: ClaudeLocator = ClaudeLocator(), status: AIStatus,
        configuration: @escaping @MainActor () -> AIConfiguration, now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.host = host
        self.loader = loader
        caller = AICaller(host: host, runner: runner, locator: locator, status: status, now: now)
        self.configuration = configuration
        self.now = now
        loader.summarizer = self
    }

    /// T: loads the page unless its text is stored, then summarizes it – unless `canSummarize` says no.
    func summarize(_ id: Article.ID) {
        guard configuration().isEnabled else {
            status.set(PageStatus.Work(phase: .failed(AIStatus.State.offMessage), summary: true), for: id)
            return
        }
        prepare(id)
    }

    /// Shift+S: like T, but also when AI is off – then the page is still loaded and stored for later, and the summary
    /// fails with the reason (the user isn't looking at the article, the error waits in its row).
    func prepare(_ id: Article.ID) {
        guard canSummarize(id) else { return }
        loader.enqueue(id, summary: true)
    }

    /// Whether T does anything: not for a current summary, nor while one is being written (a failed one can be tried
    /// again).
    func canSummarize(_ id: Article.ID) -> Bool {
        guard let article = host.library.articles[id],
            !PageSummaryStep.isCurrent(article.pageSummary, language: configuration().languageCode)
        else { return false }
        guard let work = status[id], work.summary else { return true }
        return !work.isRunning
    }

    /// P on a saved link: loads its page again and with AI on writes a new summary of it (`PageLoader.reload`).
    func reload(_ id: Article.ID) {
        loader.reload(id, summary: configuration().isEnabled)
    }

    /// Writes the summary of the loaded page text (`PageSummarizing`).
    func summarize(_ id: Article.ID, text: String) async {
        let configuration = configuration()
        guard configuration.isEnabled else {
            fail(id, AIStatus.State.offMessage)
            return
        }
        guard let article = host.library.articles[id] else {
            status.set(nil, for: id)
            return
        }
        let request = PageSummaryStep.request(
            for: article, pageText: text, in: host.library, configuration: configuration)
        status.set(PageStatus.Work(phase: .summarizing, summary: true), for: id)
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
            case .summarized: status.set(nil, for: id)
            case .notArticle: fail(id, article.isSavedLink ? Self.notArticleLinkMessage : Self.notArticleMessage)
            case .empty: fail(id, "claude gave an empty summary")
            }
        } catch {
            fail(id, error.message)
        }
    }

    private func fail(_ id: Article.ID, _ message: String) {
        status.fail(id, message)
    }
}
