import Foundation
import Testing

@testable import Feedini

@MainActor
struct PageSummaryQueueTests {
    private let feed = Feed.stub("Tech")
    private let status = AIStatus()
    private let extractor = FakePageExtractor()
    private let article: Article
    private let host: TestLibraryHost

    private static let ok = FakeCommandRunner.Reply.structured(#"{"status":"ok","tldr":"The gist."}"#)

    init() {
        article = Article.stub("Launch", feed: feed.id)
        host = TestLibraryHost(Library(feeds: [feed], articles: [article]))
    }

    private func queue(
        _ runner: FakeCommandRunner, found: Bool = true, setting: Setting = Setting()
    ) -> PageSummaryQueue {
        PageSummaryQueue(
            host: host, extractor: extractor, runner: runner, locator: .stub(found: found), status: status,
            configuration: { AIConfiguration(isEnabled: setting.isEnabled, languageCode: setting.language) },
            now: { referenceDate })
    }

    /// AI settings changed by a test.
    final class Setting {
        var isEnabled = true
        var language = "cs"
    }

    private var stored: Article? { host.library.articles[article.id] }

    @Test func loadingStoresThePageTextOnce() async {
        let runner = FakeCommandRunner([Self.ok])
        let queue = queue(runner)

        queue.loadPage(article.id)
        #expect(status.pages[article.id] == AIStatus.PageWork(phase: .loading, summary: false))
        await queue.waitUntilIdle()

        #expect(stored?.pageText == "Text of the page \(article.link!.lastPathComponent).")
        #expect(status.pages[article.id] == nil)
        queue.loadPage(article.id)
        #expect(!queue.isRunning)
        #expect(extractor.requests == [article.link!])
        #expect(runner.calls.isEmpty)
    }

    @Test func summarizingLoadsThePageAndStoresTheSummary() async {
        let runner = FakeCommandRunner([Self.ok])
        let queue = queue(runner)

        queue.summarize(article.id)
        #expect(status.pages[article.id] == AIStatus.PageWork(phase: .loading, summary: true))
        await queue.waitUntilIdle()

        #expect(stored?.pageSummary == PageSummary(tldr: "The gist.", details: [], language: "cs", date: referenceDate))
        #expect(status.pages[article.id] == nil)
        #expect(runner.calls.count == 1)
        #expect(runner.calls.first?.value(of: "--system-prompt") == Prompts.pageSummary)
        #expect(runner.calls.first?.payload["page_text"] as? String == stored?.pageText)
        #expect(status.calls.first?.step == "Summarize page")
        #expect(host.library.usage.first?.calls == 1)

        // A current summary: T does nothing.
        queue.summarize(article.id)
        #expect(!queue.isRunning)
    }

    @Test func requestsForTheSameArticleAreIgnoredButTContinuesARunningP() async {
        let runner = FakeCommandRunner([Self.ok])
        let queue = queue(runner)

        queue.loadPage(article.id)
        queue.summarize(article.id)
        queue.summarize(article.id)
        #expect(status.pages[article.id] == AIStatus.PageWork(phase: .loading, summary: true))
        await queue.waitUntilIdle()

        #expect(extractor.requests.count == 1)
        #expect(runner.calls.count == 1)
        #expect(stored?.pageSummary != nil)
    }

    @Test func aNewLanguageSummarizesAgainWithoutLoading() async {
        let runner = FakeCommandRunner([Self.ok])
        let setting = Setting()
        let queue = queue(runner, setting: setting)
        queue.summarize(article.id)
        await queue.waitUntilIdle()

        setting.language = "en"
        queue.summarize(article.id)
        #expect(status.pages[article.id] == AIStatus.PageWork(phase: .summarizing, summary: true))
        #expect(status.message == "Summarizing page…")
        #expect(status.isWorking)
        await queue.waitUntilIdle()

        #expect(extractor.requests.count == 1)
        #expect(runner.calls.count == 2)
        #expect(runner.calls.last?.payload["output_language"] as? String == "English")
        #expect(stored?.pageSummary?.language == "en")
    }

    @Test func runsAtMostTwoAtATime() async {
        let others = (0..<3).map { Article.stub("Other \($0)", feed: feed.id) }
        for other in others {
            host.library.articles[other.id] = other
        }
        let queue = queue(FakeCommandRunner([Self.ok]))

        for id in [article.id] + others.map(\.id) {
            queue.loadPage(id)
        }
        #expect(status.pages.count == 4)
        await queue.waitUntilIdle()

        #expect(extractor.maxRunning == PageSummaryQueue.maxParallel)
        #expect(extractor.requests.count == 4)
        #expect(host.library.articles.values.allSatisfy { $0.pageText != nil })
    }

    @Test func aPageThatDoesNotLoadShowsTheError() async {
        extractor.result = { _ in .failure(.http(status: 404)) }
        let runner = FakeCommandRunner([Self.ok])
        let queue = queue(runner)

        queue.summarize(article.id)
        await queue.waitUntilIdle()

        #expect(
            status.pages[article.id]
                == AIStatus.PageWork(phase: .failed(PageError.http(status: 404).message), summary: true))
        #expect(stored?.pageText == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func aPageWithoutTheArticleIsLoadedAgainNextTime() async {
        let runner = FakeCommandRunner([
            .structured(#"{"status":"not_article","tldr":""}"#), Self.ok,
        ])
        let queue = queue(runner)

        queue.summarize(article.id)
        await queue.waitUntilIdle()
        #expect(
            status.pages[article.id]
                == AIStatus.PageWork(phase: .failed(PageSummaryQueue.notArticleMessage), summary: true))
        #expect(stored?.pageText == nil)

        queue.summarize(article.id)
        await queue.waitUntilIdle()
        #expect(extractor.requests.count == 2)
        #expect(stored?.pageSummary?.tldr == "The gist.")
        #expect(status.pages[article.id] == nil)
    }

    @Test func emptyAnswersAndFailedCallsShowAnError() async {
        let runner = FakeCommandRunner([
            .structured(#"{"status":"ok","tldr":" "}"#), .error(.timedOut(.seconds(120))),
        ])
        let queue = queue(runner)

        queue.summarize(article.id)
        await queue.waitUntilIdle()
        #expect(status.pages[article.id]?.phase == .failed("claude gave an empty summary"))

        queue.summarize(article.id)
        await queue.waitUntilIdle()
        #expect(status.pages[article.id]?.phase == .failed("claude didn't answer in time"))
        #expect(extractor.requests.count == 1)
        #expect(stored?.pageSummary == nil)
    }

    @Test func withoutAISummarizingSaysWhyAndPreviewStillWorks() async {
        let runner = FakeCommandRunner([Self.ok])
        let setting = Setting()
        setting.isEnabled = false
        let queue = queue(runner, setting: setting)

        queue.summarize(article.id)
        #expect(
            status.pages[article.id] == AIStatus.PageWork(phase: .failed(AIStatus.State.offMessage), summary: true))
        #expect(!queue.isRunning)

        queue.loadPage(article.id)
        await queue.waitUntilIdle()
        #expect(stored?.pageText != nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func aiTurnedOffWhileThePageLoadsStopsBeforeTheCall() async {
        let runner = FakeCommandRunner([Self.ok])
        let setting = Setting()
        let queue = queue(runner, setting: setting)

        queue.summarize(article.id)
        setting.isEnabled = false
        await queue.waitUntilIdle()

        #expect(status.pages[article.id]?.phase == .failed(AIStatus.State.offMessage))
        #expect(stored?.pageText != nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func canSummarizeUnlessCurrentOrBeingWritten() async {
        let runner = FakeCommandRunner([.error(.timedOut(.seconds(120))), Self.ok])
        let setting = Setting()
        let queue = queue(runner, setting: setting)
        #expect(queue.canSummarize(article.id))
        #expect(!queue.canSummarize(UUID()))

        queue.summarize(article.id)
        #expect(!queue.canSummarize(article.id))
        await queue.waitUntilIdle()
        // Failed: it can be tried again.
        #expect(queue.canSummarize(article.id))

        queue.summarize(article.id)
        await queue.waitUntilIdle()
        #expect(!queue.canSummarize(article.id))
        setting.language = "en"
        #expect(queue.canSummarize(article.id))
    }

    @Test func openingThePageForgetsItsTextUnlessItIsBeingLoaded() async {
        let queue = queue(FakeCommandRunner([Self.ok]))
        queue.loadPage(article.id)
        queue.pageOpened(article.id)
        await queue.waitUntilIdle()
        #expect(stored?.pageText != nil)

        queue.pageOpened(article.id)
        #expect(stored?.pageText == nil)
    }

    @Test func withoutClaudeSummarizingSaysWhy() async {
        let runner = FakeCommandRunner([Self.ok])
        let queue = queue(runner, found: false)

        queue.summarize(article.id)
        await queue.waitUntilIdle()

        #expect(status.pages[article.id]?.phase == .failed("claude not found"))
        #expect(stored?.pageText != nil)
    }

    @Test func anArticleWithoutALinkOrGoneFails() async {
        host.library.articles[article.id]?.link = nil
        let queue = queue(FakeCommandRunner([Self.ok]))

        queue.loadPage(article.id)
        await queue.waitUntilIdle()
        #expect(status.pages[article.id]?.phase == .failed("The article has no link to its page."))

        queue.loadPage(UUID())
        queue.summarize(UUID())
        #expect(!queue.isRunning)
    }
}
