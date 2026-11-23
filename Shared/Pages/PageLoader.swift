import Foundation

/// Writes the summary of a page whose text was loaded (on the Mac `PageSummaryQueue`).
@MainActor
protocol PageSummarizing: AnyObject {
    /// Summarizes the page text of the article and records the outcome in the page status.
    func summarize(_ id: Article.ID, text: String) async
}

/// Loads source pages (P, Save Link), only on the user's request, at most `maxParallel` at a time; on the Mac the
/// work may go on to a summary of the page (`PageSummarizing`), in the same slot.
///
/// The page text is stored (`LibraryHost.storePageText`), so a summary after P doesn't load the page again. A request
/// for an article already being worked on is ignored, except that asking for a summary makes a running P go on to
/// it. Nothing is retried by itself: it is the user's action, the error is shown in the detail. The work and whether
/// a summary was asked for are kept in `PageStatus` only.
///
/// A saved link (`SavedLink`) has no feed text, so its page text is all it has: P loads it again instead (`reload`),
/// keeping the stored one until the new one is there, and opening the page (V) doesn't forget it. Loading it fills in
/// the title, source and date from the page.
@MainActor
final class PageLoader {
    static let maxParallel = 2

    let status: PageStatus
    /// Writes the summaries that were asked for; without one (iOS) nothing asks for them.
    weak var summarizer: (any PageSummarizing)?
    private unowned let host: any LibraryHost
    private let extractor: any PageExtracting
    private var waiting: [Article.ID] = []
    private var tasks: [Article.ID: Task<Void, Never>] = [:]
    /// Saved links whose page is loaded again even though its text is stored (`reload`).
    private var reloading: Set<Article.ID> = []

    init(host: any LibraryHost, extractor: any PageExtracting, status: PageStatus = PageStatus()) {
        self.host = host
        self.extractor = extractor
        self.status = status
    }

    /// P: loads the page's text unless it is stored.
    func loadPage(_ id: Article.ID) {
        guard host.library.articles[id] != nil, !host.library.pageTextIDs.contains(id) else { return }
        enqueue(id, summary: false)
    }

    /// The user opened the page in the window, where they may accept cookies or log in: the stored text is forgotten,
    /// so the next P (or summary) loads the page again. A saved link keeps it (`Library.forgetPageText`); P loads it
    /// again.
    func pageOpened(_ id: Article.ID) {
        guard host.library.pageTextIDs.contains(id), !isWorking(on: id) else { return }
        host.update { $0.forgetPageText(id) }
    }

    /// P on a saved link: loads its page again – after the user accepted cookies or logged in with V –, then goes on
    /// to a new summary if asked. The stored text stays until the new one is stored, also when loading fails.
    func reload(_ id: Article.ID, summary: Bool = false) {
        guard host.library.articles[id] != nil, !isWorking(on: id) else { return }
        reloading.insert(id)
        enqueue(id, summary: summary)
    }

    /// Loads the page unless its text is stored (or `summary` is false and it is), then goes on to the summary if
    /// asked. For an article already being worked on, asking for a summary makes the work go on to it.
    func enqueue(_ id: Article.ID, summary: Bool) {
        if isWorking(on: id) {
            if summary, let work = status[id] {
                status.set(PageStatus.Work(phase: work.phase, summary: true), for: id)
            }
            return
        }
        let loads = reloading.contains(id) || !host.library.pageTextIDs.contains(id)
        status.set(PageStatus.Work(phase: loads ? .loading : .summarizing, summary: summary), for: id)
        waiting.append(id)
        fill()
    }

    /// Whether the article's page is being worked on or waits for it.
    func isWorking(on id: Article.ID) -> Bool {
        tasks[id] != nil || waiting.contains(id)
    }

    var isRunning: Bool { !tasks.isEmpty || !waiting.isEmpty }

    /// Waits until nothing runs or waits (tests).
    func waitUntilIdle() async {
        while let task = tasks.values.first {
            await task.value
        }
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
            status.set(nil, for: id)
            return
        }
        var text = reloads ? nil : await host.pageText(id)
        if text == nil {
            text = await load(article)
        }
        guard let text else { return }
        guard status[id]?.summary == true, let summarizer else {
            status.set(nil, for: id)
            return
        }
        await summarizer.summarize(article.id, text: text)
    }

    /// Loads and stores the page's text; `nil` when it couldn't be loaded.
    private func load(_ article: Article) async -> String? {
        guard let link = article.link else {
            status.fail(article.id, "The article has no link to its page.")
            return nil
        }
        let summary = status[article.id]?.summary ?? false
        status.set(PageStatus.Work(phase: .loading, summary: summary), for: article.id)
        let started = ContinuousClock.now
        let content: PageContent
        do {
            content = try await extractor.extract(link)
        } catch {
            status.fail(article.id, error.message)
            Log.feeds.error("Loading a page failed: \(error.message, privacy: .public)")
            return nil
        }
        let text = content.text
        do {
            try await host.storePageText(text, for: article.id)
        } catch {
            status.fail(article.id, "The page text couldn't be stored: \(error.localizedDescription)")
            Log.store.error("Storing a page text failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        host.update { $0.applyPageMetadata(content.metadata, to: article.id) }
        let duration = String(describing: ContinuousClock.now - started)
        Log.feeds.info("Loaded a page: \(text.count) characters in \(duration, privacy: .public)")
        return text
    }
}
