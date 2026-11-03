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
        var isEnabled: Bool
        var language = "cs"

        init(isEnabled: Bool = true) {
            self.isEnabled = isEnabled
        }
    }

    private var stored: Article? { host.library.articles[article.id] }
    private var storedText: String? { host.storedText(article.id) }

    @Test func loadingStoresThePageTextOnce() async {
        let runner = FakeCommandRunner([Self.ok])
        let queue = queue(runner)

        queue.loadPage(article.id)
        #expect(status.pages[article.id] == AIStatus.PageWork(phase: .loading, summary: false))
        await queue.waitUntilIdle()

        #expect(storedText == "Text of the page \(article.link!.lastPathComponent).")
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
        #expect(runner.calls.first?.payload["page_text"] as? String == storedText)
        #expect(status.calls.first?.step == "Summarize page")
        #expect(host.library.usage.first?.calls == 1)

        // A current summary: T does nothing.
        queue.summarize(article.id)
        #expect(!queue.isRunning)
    }

    @Test func preparingLoadsAndSummarizesUnlessTheSummaryIsCurrent() async {
        let runner = FakeCommandRunner([Self.ok])
        let queue = queue(runner)

        queue.prepare(article.id)
        #expect(status.pages[article.id] == AIStatus.PageWork(phase: .loading, summary: true))
        await queue.waitUntilIdle()
        #expect(stored?.pageSummary?.tldr == "The gist.")

        queue.prepare(article.id)
        #expect(!queue.isRunning)
        #expect(extractor.requests.count == 1)
    }

    @Test func preparingWithoutAIStillStoresThePageAndSaysWhy() async {
        let runner = FakeCommandRunner([])
        let setting = Setting()
        setting.isEnabled = false
        let queue = queue(runner, setting: setting)

        queue.prepare(article.id)
        await queue.waitUntilIdle()

        #expect(storedText != nil)
        #expect(
            status.pages[article.id]
                == AIStatus.PageWork(phase: .failed(AIStatus.State.offMessage), summary: true))
        #expect(runner.calls.isEmpty)

        // Once AI is on, the stored text is summarized without loading the page again.
        setting.isEnabled = true
        let again = self.queue(FakeCommandRunner([Self.ok]), setting: setting)
        again.prepare(article.id)
        await again.waitUntilIdle()
        #expect(stored?.pageSummary != nil)
        #expect(extractor.requests.count == 1)
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
        #expect(host.library.pageTextIDs == Set(host.library.articles.keys))
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
        #expect(storedText == nil)
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
        #expect(storedText == nil)

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
        #expect(storedText != nil)
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
        #expect(storedText != nil)
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
        #expect(storedText != nil)

        queue.pageOpened(article.id)
        #expect(storedText == nil)
    }

    @Test func withoutClaudeSummarizingSaysWhy() async {
        let runner = FakeCommandRunner([Self.ok])
        let queue = queue(runner, found: false)

        queue.summarize(article.id)
        await queue.waitUntilIdle()

        #expect(status.pages[article.id]?.phase == .failed("claude not found"))
        #expect(storedText != nil)
    }

    @Test func aTextThatCannotBeStoredShowsTheErrorAndIsNotSummarized() async {
        host.failsStoringPageTexts = true
        let runner = FakeCommandRunner([Self.ok])
        let queue = queue(runner)

        queue.summarize(article.id)
        await queue.waitUntilIdle()

        guard case .failed(let message) = status.pages[article.id]?.phase else {
            Issue.record("No error shown")
            return
        }
        #expect(message.hasPrefix("The page text couldn't be stored: "))
        #expect(host.library.pageTextIDs.isEmpty)
        #expect(runner.calls.isEmpty)
    }

    @Test func aStoredTextThatIsGoneIsLoadedAgain() async {
        let runner = FakeCommandRunner([Self.ok])
        host.library.pageTextIDs = [article.id]
        let queue = queue(runner)

        queue.summarize(article.id)
        #expect(status.pages[article.id] == AIStatus.PageWork(phase: .summarizing, summary: true))
        await queue.waitUntilIdle()

        #expect(extractor.requests == [article.link!])
        #expect(runner.calls.first?.payload["page_text"] as? String == storedText)
        #expect(stored?.pageSummary?.tldr == "The gist.")
    }

    @Test func aStoredTextIsSummarizedWithoutLoading() async {
        let runner = FakeCommandRunner([Self.ok])
        host.library.pageTextIDs = [article.id]
        host.pageTexts[article.id] = "The stored text."
        let queue = queue(runner)

        queue.loadPage(article.id)
        #expect(!queue.isRunning)
        queue.summarize(article.id)
        await queue.waitUntilIdle()

        #expect(extractor.requests.isEmpty)
        #expect(runner.calls.first?.payload["page_text"] as? String == "The stored text.")
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

    // MARK: Saved links

    /// A saved link in the host's library, as Save Link… adds it.
    private func savedLink() -> Article.ID {
        host.library.saveLink(URL(string: "https://example.com/essay")!, at: referenceDate).articleID
    }

    @Test func loadingASavedLinkFillsInWhatThePageSays() async {
        extractor.metadata = { _ in
            PageMetadata(title: "An Essay", site: "Example Magazine", author: "A. Writer", published: .hours(-5))
        }
        let id = savedLink()
        let queue = queue(FakeCommandRunner([Self.ok]))

        queue.prepare(id)
        await queue.waitUntilIdle()

        let link = host.library.articles[id]
        #expect(link?.title == "An Essay")
        #expect(link?.site == "Example Magazine")
        #expect(link?.author == "A. Writer")
        #expect(link?.published == .hours(-5))
        #expect(link?.link == URL(string: "https://example.com/essay"))
        #expect(link?.pageSummary?.tldr == "The gist.")
        #expect(host.storedText(id) == "Text of the page essay.")
        // A feed's article keeps what its feed says.
        queue.loadPage(article.id)
        await queue.waitUntilIdle()
        #expect(stored?.title == "Launch")
        #expect(stored?.author == nil)
    }

    @Test func emptyMetadataKeepsWhatTheLinkHas() async {
        let id = savedLink()
        let queue = queue(FakeCommandRunner([]))

        queue.loadPage(id)
        await queue.waitUntilIdle()

        #expect(host.library.articles[id]?.title == "example.com/essay")
        #expect(host.library.articles[id]?.site == "example.com")
    }

    @Test func reloadingASavedLinkReplacesItsTextAndSummary() async {
        let id = savedLink()
        let runner = FakeCommandRunner([
            Self.ok, .structured(#"{"status":"ok","tldr":"The new gist."}"#),
        ])
        let queue = queue(runner)
        queue.prepare(id)
        await queue.waitUntilIdle()
        extractor.result = { _ in .success("The page after logging in.") }

        queue.reload(id)
        #expect(status.pages[id] == AIStatus.PageWork(phase: .loading, summary: true))
        queue.reload(id)
        await queue.waitUntilIdle()

        #expect(extractor.requests.count == 2)
        #expect(host.storedText(id) == "The page after logging in.")
        #expect(host.library.articles[id]?.pageSummary?.tldr == "The new gist.")
        #expect(runner.calls.last?.payload["page_text"] as? String == "The page after logging in.")
        #expect(status.pages[id] == nil)
    }

    @Test func reloadingWithoutAIOnlyLoadsTheText() async {
        let id = savedLink()
        let runner = FakeCommandRunner([])
        let queue = queue(runner, setting: Setting(isEnabled: false))

        queue.reload(id)
        await queue.waitUntilIdle()

        #expect(host.storedText(id) == "Text of the page essay.")
        #expect(runner.calls.isEmpty)
        queue.reload(UUID())
        #expect(!queue.isRunning)
    }

    @Test func aFailedReloadKeepsTheStoredText() async {
        let id = savedLink()
        let queue = queue(FakeCommandRunner([Self.ok]))
        queue.prepare(id)
        await queue.waitUntilIdle()
        extractor.result = { _ in .failure(.timedOut) }

        queue.reload(id)
        await queue.waitUntilIdle()

        #expect(host.storedText(id) == "Text of the page essay.")
        #expect(host.library.articles[id]?.pageSummary?.tldr == "The gist.")
        #expect(status.pages[id] == AIStatus.PageWork(phase: .failed(PageError.timedOut.message), summary: true))
    }

    @Test func aSavedLinkKeepsItsTextWhenOpenedOrNotAnArticle() async {
        let id = savedLink()
        let queue = queue(FakeCommandRunner([.structured(#"{"status":"not_article","tldr":""}"#)]))

        queue.prepare(id)
        await queue.waitUntilIdle()
        queue.pageOpened(id)

        #expect(host.storedText(id) == "Text of the page essay.")
        #expect(
            status.pages[id] == AIStatus.PageWork(phase: .failed(PageSummaryQueue.notArticleLinkMessage), summary: true)
        )
    }
}
