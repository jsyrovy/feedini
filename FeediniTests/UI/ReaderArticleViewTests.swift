import Foundation
import Testing

@testable import Feedini

/// The preferred view of an article (`Preferences.articleView`): what the detail shows on moving onto it.
@MainActor
struct ReaderArticleViewTests {
    let feed = Feed.stub("Tech")
    let extractor = FakePageExtractor()
    let services: MacServices
    let model: AppModel
    let reader: Reader
    /// Opened to end every wait for the cursor to settle; a cancelled wait throws.
    let settled = OneShotSignal()
    let lone: Article
    let other: Article
    let third: Article
    let first: Article
    let story: Story

    init() {
        services = MacServices.test(extractor: extractor)
        model = services.model
        reader = Reader(services: services) { [settled] _ in
            await settled.wait()
            try Task.checkCancellation()
        }
        lone = Article.stub("Lone", feed: feed.id, hours: -1)
        other = Article.stub("Other", feed: feed.id, hours: -2)
        third = Article.stub("Third", feed: feed.id, hours: -3)
        first = Article.stub("First", feed: feed.id, hours: -4)
        let second = Article.stub("Second", feed: feed.id, hours: -5)
        story = Story(title: "Story", articleIDs: [first.id, second.id])
        let library = Library(feeds: [feed], articles: [lone, other, third, first, second], stories: [story])
        model.update { $0 = library }
    }

    /// Lets the cursor settle and waits until the page it loads is stored.
    func settle() async {
        settled.fire()
        await reader.waitUntilSettled()
        await model.pageLoader.waitUntilIdle()
    }

    @Test func theFeedTextIsTheDefault() async {
        reader.visit(.story(.loose(lone.id)))

        #expect(reader.shown == nil)
        #expect(reader.waitingArticle == nil)
        await settle()
        #expect(extractor.requests.isEmpty)
    }

    @Test func pageTextLoadsThePageOnceTheCursorStays() async {
        model.preferences.articleView = .pageText
        reader.visit(.story(.loose(lone.id)))

        #expect(reader.previewArticle == lone.id)
        #expect(reader.waitingArticle == lone.id)
        #expect(extractor.requests.isEmpty)

        await settle()
        #expect(reader.waitingArticle == nil)
        #expect(extractor.requests == [lone.link!])
        #expect(model.library.pageTextIDs == [lone.id])
    }

    @Test func walkingTheListLoadsOnlyThePageWhereTheCursorStays() async {
        model.preferences.articleView = .pageText
        reader.handle(.next)
        reader.handle(.next)
        reader.handle(.next)
        #expect(reader.previewArticle == third.id)

        await settle()
        #expect(extractor.requests == [third.link!])
    }

    @Test func aStoredPageTextShowsAtOnce() async {
        model.loadPage(lone.id)
        await model.pageLoader.waitUntilIdle()
        model.preferences.articleView = .pageText

        reader.visit(.story(.loose(lone.id)))

        #expect(reader.previewArticle == lone.id)
        #expect(reader.waitingArticle == nil)
        #expect(extractor.requests.count == 1)
    }

    @Test func aStoryWithSeveralArticlesAndAnArticleWithoutALinkShowTheirText() async {
        model.preferences.articleView = .webPage
        model.update { $0.articles[other.id]?.link = nil }

        reader.visit(.story(.story(story.id)))
        #expect(reader.shown == nil)
        reader.visit(.story(.loose(other.id)))
        #expect(reader.shown == nil)

        reader.visit(.article(.story(story.id), first.id))
        #expect(reader.pageArticle == first.id)
        await settle()
    }

    @Test func pSwitchesFromThePreferredPageTextToTheFeedTextAndBack() async {
        model.preferences.articleView = .pageText
        reader.visit(.story(.loose(lone.id)))

        reader.handle(.preview)
        #expect(reader.shown == nil)
        #expect(reader.waitingArticle == nil)

        reader.handle(.preview)
        #expect(reader.previewArticle == lone.id)
        // P loads at once: it doesn't wait for the cursor to settle.
        #expect(reader.waitingArticle == nil)
        #expect(model.pageStatus[lone.id]?.phase == .loading)
        await settle()
        #expect(extractor.requests == [lone.link!])
    }

    @Test func theWebPageShowsOnceTheCursorStaysAndKeepsTheStoredText() async {
        model.loadPage(lone.id)
        await model.pageLoader.waitUntilIdle()
        model.preferences.articleView = .webPage

        reader.visit(.story(.loose(lone.id)))
        #expect(reader.pageArticle == lone.id)
        #expect(reader.waitingArticle == lone.id)

        await settle()
        #expect(reader.waitingArticle == nil)
        #expect(reader.pageArticle == lone.id)
        #expect(model.library.pageTextIDs == [lone.id])
        #expect(extractor.requests.count == 1)
    }

    @Test func vAndEscapeGoBackToTheFeedTextAndVOpensThePageAgain() async {
        model.loadPage(lone.id)
        await model.pageLoader.waitUntilIdle()
        model.preferences.articleView = .webPage
        reader.visit(.story(.loose(lone.id)))

        reader.handle(.open)
        #expect(reader.shown == nil)
        #expect(reader.waitingArticle == nil)
        #expect(model.library.pageTextIDs == [lone.id])

        // Opened explicitly, the page forgets its stored text, as V always does.
        reader.handle(.open)
        #expect(reader.pageArticle == lone.id)
        #expect(reader.waitingArticle == nil)
        #expect(model.library.pageTextIDs.isEmpty)

        reader.handle(.escape)
        #expect(reader.shown == nil)
    }

    @Test func aDoubleClickShowsAWaitingPageAtOnceAndNeverClosesIt() async {
        model.preferences.articleView = .webPage
        reader.visit(.story(.loose(lone.id)))

        reader.openOnDoubleClick()
        #expect(reader.pageArticle == lone.id)
        #expect(reader.waitingArticle == nil)
        reader.openOnDoubleClick()
        #expect(reader.pageArticle == lone.id)

        model.preferences.articleView = .feedText
        reader.visit(.story(.loose(other.id)))
        reader.openOnDoubleClick()
        #expect(reader.pageArticle == other.id)
        reader.openOnDoubleClick()
        #expect(reader.pageArticle == other.id)
        await settle()
    }

    @Test func undoOnTheRowShownKeepsItsPage() async {
        model.preferences.articleView = .webPage
        reader.visit(.story(.loose(lone.id)))
        await settle()
        reader.handle(.toggleRead)

        reader.undo()

        #expect(reader.cursor == .story(.loose(lone.id)))
        #expect(reader.pageArticle == lone.id)
        #expect(reader.waitingArticle == nil)
    }

    @Test func undoOnTheRowShownKeepsWhatTheUserChose() async {
        // The page opened with V stays with the feed text preferred.
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.open)
        reader.handle(.toggleRead)
        reader.undo()
        #expect(reader.pageArticle == lone.id)

        // The feed text after Esc stays with the web page preferred.
        model.preferences.articleView = .webPage
        reader.visit(.story(.loose(other.id)))
        reader.handle(.escape)
        reader.handle(.toggleRead)
        reader.undo()
        #expect(reader.shown == nil)
        #expect(reader.waitingArticle == nil)

        // A move onto another row shows the preferred view again.
        reader.visit(.story(.loose(lone.id)))
        #expect(reader.pageArticle == lone.id)
        await settle()
    }

    @Test func undoKeepsThePageOfAnArticleTheAIMovedIntoAStory() async {
        model.preferences.articleView = .webPage
        reader.visit(.story(.loose(lone.id)))
        await settle()
        let joined = Story(title: "Lone", articleIDs: [lone.id])
        model.update { $0.stories[joined.id] = joined }
        #expect(reader.cursor == .story(.story(joined.id)))
        reader.handle(.toggleRead)

        reader.undo()

        #expect(reader.pageArticle == lone.id)
        #expect(reader.waitingArticle == nil)
    }

    @Test func aSavedLinkShowsItsPageTextOrItsWebPage() async throws {
        services.preferences.aiEnabled = false
        let id = try model.saveLink("example.com/essay").articleID
        await model.pageLoader.waitUntilIdle()
        reader.selection = .saved

        model.preferences.articleView = .pageText
        reader.visit(.story(.savedArticle(id)))
        #expect(reader.shown == nil)

        reader.visit(nil)
        model.preferences.articleView = .webPage
        reader.visit(.story(.savedArticle(id)))
        #expect(reader.pageArticle == id)
        await settle()
        #expect(model.library.pageTextIDs == [id])
    }

    @Test func leavingTheArticleStopsWaitingAndLoadsNothing() async {
        model.preferences.articleView = .pageText
        reader.visit(.story(.loose(lone.id)))

        reader.handle(.markAllRead)

        #expect(reader.shown == nil)
        #expect(reader.waitingArticle == nil)
        await settle()
        #expect(extractor.requests.isEmpty)
    }

    @Test func aNewSelectionShowsTheFeedTextAgain() {
        model.preferences.articleView = .webPage
        reader.visit(.story(.loose(lone.id)))

        reader.selection = .feed(feed.id)

        #expect(reader.shown == nil)
        #expect(reader.waitingArticle == nil)
    }
}
