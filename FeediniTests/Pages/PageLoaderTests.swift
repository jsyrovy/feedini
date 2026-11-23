import Foundation
import Testing

@testable import Feedini

/// The page loader on its own, as on iOS: no summaries. With the Mac's summaries: `PageSummaryQueueTests`.
@MainActor
struct PageLoaderTests {
    private let feed = Feed.stub("Tech")
    private let status = PageStatus()
    private let extractor = FakePageExtractor()
    private let article: Article
    private let host: TestLibraryHost

    init() {
        article = Article.stub("Launch", feed: feed.id)
        host = TestLibraryHost(Library(feeds: [feed], articles: [article]))
    }

    private func loader() -> PageLoader {
        PageLoader(host: host, extractor: extractor, status: status)
    }

    private var storedText: String? { host.storedText(article.id) }

    /// A saved link in the host's library, as Save Link… adds it.
    private func savedLink() -> Article.ID {
        host.library.saveLink(URL(string: "https://example.com/essay")!, at: referenceDate).articleID
    }

    @Test func loadingStoresThePageTextOnce() async {
        let loader = loader()

        loader.loadPage(article.id)
        #expect(status[article.id] == PageStatus.Work(phase: .loading, summary: false))
        await loader.waitUntilIdle()

        #expect(storedText == "Text of the page \(article.link!.lastPathComponent).")
        #expect(status[article.id] == nil)
        loader.loadPage(article.id)
        #expect(!loader.isRunning)
        #expect(extractor.requests == [article.link!])
    }

    @Test func runsAtMostTwoAtATime() async {
        let others = (0..<3).map { Article.stub("Other \($0)", feed: feed.id) }
        for other in others {
            host.library.articles[other.id] = other
        }
        let loader = loader()

        for id in [article.id] + others.map(\.id) {
            loader.loadPage(id)
        }
        #expect(status.pages.count == 4)
        await loader.waitUntilIdle()

        #expect(extractor.maxRunning == PageLoader.maxParallel)
        #expect(extractor.requests.count == 4)
        #expect(host.library.pageTextIDs == Set(host.library.articles.keys))
    }

    @Test func openingThePageForgetsItsTextUnlessItIsBeingLoaded() async {
        let loader = loader()
        loader.loadPage(article.id)
        loader.pageOpened(article.id)
        await loader.waitUntilIdle()
        #expect(storedText != nil)

        loader.pageOpened(article.id)
        #expect(storedText == nil)
    }

    @Test func emptyMetadataKeepsWhatTheLinkHas() async {
        let id = savedLink()
        let loader = loader()

        loader.loadPage(id)
        await loader.waitUntilIdle()

        #expect(host.library.articles[id]?.title == "example.com/essay")
        #expect(host.library.articles[id]?.site == "example.com")
    }

    @Test func withoutASummarizerASummaryRequestOnlyLoadsThePage() async {
        let loader = loader()

        loader.enqueue(article.id, summary: true)
        #expect(status[article.id] == PageStatus.Work(phase: .loading, summary: true))
        await loader.waitUntilIdle()

        #expect(storedText != nil)
        #expect(status.pages.isEmpty)
    }

    @Test func reloadingASavedLinkReplacesItsText() async {
        let id = savedLink()
        let loader = loader()
        loader.loadPage(id)
        await loader.waitUntilIdle()
        extractor.result = { _ in .success("The page after logging in.") }

        loader.reload(id)
        #expect(status[id] == PageStatus.Work(phase: .loading, summary: false))
        loader.reload(id)
        await loader.waitUntilIdle()

        #expect(extractor.requests.count == 2)
        #expect(host.storedText(id) == "The page after logging in.")
        loader.reload(UUID())
        #expect(!loader.isRunning)
    }
}
