import Foundation
import Testing

@testable import Feedini

@MainActor
struct ReaderTests {
    private let feed = Feed.stub("Tech")
    private let extractor = FakePageExtractor()
    private let model: AppModel
    private let reader: Reader
    private let lone: Article
    private let first: Article
    private let second: Article
    private let story: Story

    init() {
        model = AppModel.test(extractor: extractor)
        reader = Reader(model: model)
        lone = Article.stub("Lone", feed: feed.id, hours: -1)
        first = Article.stub("First", feed: feed.id, hours: -2)
        second = Article.stub("Second", feed: feed.id, hours: -3)
        story = Story(title: "Story", articleIDs: [first.id, second.id])
        let library = Library(feeds: [feed], articles: [lone, first, second], stories: [story])
        model.update { $0 = library }
    }

    private func isRead(_ article: Article) -> Bool {
        model.library.articles[article.id]?.isRead == true
    }

    @Test func visitingReadsButKeepsTheEntryInTheList() {
        reader.visit(.story(.loose(lone.id)))

        #expect(isRead(lone))
        #expect(reader.entries.map(\.title) == ["Lone", "Story"])
        #expect(reader.cursorArticle == model.library.articles[lone.id])
    }

    @Test func jAndKWalkAndACollapsedStoryIsReadAsAWhole() {
        reader.handle(.next)
        reader.handle(.next)

        #expect(reader.cursor == .story(.story(story.id)))
        #expect(isRead(first) && isRead(second))
        #expect(reader.cursorArticle == nil)
    }

    @Test func insideAnExpandedStoryArticlesAreReadOneByOne() {
        reader.visit(.story(.story(story.id)))
        model.markUnread([first.id, second.id])
        reader.handle(.expand)
        reader.handle(.next)

        #expect(reader.cursor == .article(.story(story.id), first.id))
        #expect(isRead(first))
        #expect(!isRead(second))

        reader.handle(.collapse)
        #expect(reader.cursor == .story(.story(story.id)))
        #expect(reader.expanded.isEmpty)
    }

    @Test func clickingAnArticleOfAStoryExpandsIt() {
        reader.visit(.article(.story(story.id), second.id))
        #expect(reader.expanded == [.story(story.id)])
        #expect(isRead(second) && !isRead(first))
    }

    @Test func changingTheSelectionDropsReadEntries() {
        reader.visit(.story(.loose(lone.id)))
        reader.selection = .feed(feed.id)

        #expect(reader.entries.map(\.title) == ["Story"])
        #expect(reader.cursor == nil)
    }

    @Test func toggleReadKeepsTheEntry() {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.toggleRead)
        #expect(!isRead(lone))
        reader.toggleRead(.story(.loose(lone.id)))
        #expect(isRead(lone))
        #expect(reader.entries.count == 2)
    }

    @Test func markAllReadEmptiesTheList() {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.markAllRead)

        #expect(reader.entries.isEmpty)
        #expect(reader.cursor == nil)
        #expect(isRead(first) && isRead(second))
    }

    @Test func openingInTheWindowShowsThePageAndEscapeGoesBack() {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.open)
        #expect(reader.pageArticle == lone.id)

        let requests = reader.listFocusRequests
        reader.handle(.escape)
        #expect(reader.pageArticle == nil)
        #expect(reader.listFocusRequests == requests + 1)
    }

    @Test func movingClosesThePage() {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.open)
        reader.handle(.next)
        #expect(reader.pageArticle == nil)
    }

    @Test func toggleExpandedFromTheChevron() {
        reader.visit(.article(.story(story.id), first.id))
        reader.toggleExpanded(.story(story.id))
        #expect(reader.expanded.isEmpty)
        #expect(reader.cursor == .story(.story(story.id)))
        reader.toggleExpanded(.story(story.id))
        #expect(reader.expanded == [.story(story.id)])
    }

    @Test func pTogglesThePageTextAndLoadsItOnce() async {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.preview)
        #expect(reader.previewArticle == lone.id)
        await model.pageQueue?.waitUntilIdle()
        #expect(model.library.articles[lone.id]?.pageText != nil)

        reader.handle(.preview)
        #expect(reader.previewArticle == nil)
        reader.handle(.preview)
        #expect(reader.previewArticle == lone.id)
        #expect(extractor.requests.count == 1)

        reader.handle(.next)
        #expect(reader.previewArticle == nil)
    }

    @Test func pFromTheSourcePageShowsThePageText() async {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.open)
        reader.handle(.preview)
        #expect(reader.pageArticle == nil)
        #expect(reader.previewArticle == lone.id)
        await model.pageQueue?.waitUntilIdle()
    }

    @Test func openingThePageInTheWindowForgetsItsText() async {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.preview)
        await model.pageQueue?.waitUntilIdle()

        reader.handle(.open)
        #expect(reader.pageArticle == lone.id)
        #expect(reader.previewArticle == nil)
        #expect(model.library.articles[lone.id]?.pageText == nil)
    }

    @Test func tSummarizesThePageAndLeavesTheSourcePage() async {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.open)
        reader.handle(.summarizePage)

        #expect(reader.pageArticle == nil)
        #expect(model.aiStatus.pages[lone.id]?.summary == true)
        await model.pageQueue?.waitUntilIdle()
        #expect(extractor.requests == [lone.link!])
    }

    @Test func questionMarkShowsAndHidesTheShortcuts() {
        reader.handle(.shortcuts)
        #expect(reader.isShowingShortcuts)
        reader.handle(.shortcuts)
        #expect(!reader.isShowingShortcuts)
    }

    @Test func unknownKeysAreNotHandled() {
        #expect(!reader.handle(.collapse))
    }
}

@MainActor
struct ReaderFollowsArticlesTests {
    private let feed = Feed.stub("Tech")
    private let model: AppModel
    private let reader: Reader
    private let first: Article
    private let second: Article

    init() {
        model = AppModel.test()
        reader = Reader(model: model)
        first = Article.stub("First", feed: feed.id, hours: -1)
        second = Article.stub("Second", feed: feed.id, hours: -2)
        let library = Library(feeds: [feed], articles: [first, second])
        model.update { $0 = library }
    }

    @Test func theCursorFollowsAnArticleIntoAMultiArticleStory() {
        reader.visit(.story(.loose(first.id)))
        let story = Story(title: "Story", articleIDs: [first.id, second.id])

        model.update { $0.stories[story.id] = story }

        #expect(reader.cursor == .article(.story(story.id), first.id))
        #expect(reader.expanded.contains(.story(story.id)))
        // The other article wasn't read by following.
        #expect(model.library.articles[second.id]?.isRead == false)
        #expect(reader.entries.map(\.id) == [.story(story.id)])
    }

    @Test func theCursorFollowsAnArticleIntoAStoryOfItsOwnAndStaysKept() {
        reader.visit(.story(.loose(first.id)))
        let story = Story(title: "First", articleIDs: [first.id])

        model.update { $0.stories[story.id] = story }

        #expect(reader.cursor == .story(.story(story.id)))
        #expect(reader.kept.contains(.story(story.id)))
        #expect(reader.entries.contains { $0.id == .story(story.id) })
    }
}
