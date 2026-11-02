import Foundation
import Testing

@testable import Feedini

struct KeyboardNavigationTests {
    private let feed = Feed.stub()
    private let single: StoryEntry
    private let multi: StoryEntry
    private let first: Article
    private let second: Article
    private let lone: Article

    init() {
        lone = Article.stub("Lone", feed: feed.id, hours: -1)
        first = Article.stub("First", feed: feed.id, hours: -2)
        second = Article.stub("Second", feed: feed.id, hours: -3)
        single = StoryEntry(id: .loose(lone.id), title: "Lone", articles: [lone], newArticleIDs: [])
        multi = StoryEntry(id: .story(.init()), title: "Multi", articles: [first, second], newArticleIDs: [])
    }

    private var entries: [StoryEntry.ID: StoryEntry] {
        [single.id: single, multi.id: multi]
    }

    private func action(
        _ key: ListKey, at cursor: ListRow?, expanded: Set<StoryEntry.ID> = [], opensInWindow: Bool = true,
        page: Article.ID? = nil
    ) -> KeyboardNavigation.Action {
        let rows = KeyboardNavigation.rows([single, multi], expanded: expanded)
        return KeyboardNavigation.action(
            for: key, at: cursor, entry: cursor.flatMap { entries[$0.entryID] }, rows: rows, expanded: expanded,
            opensInWindow: opensInWindow,
            pageArticle: page)
    }

    @Test func rowsIncludeTheArticlesOfExpandedStories() {
        #expect(KeyboardNavigation.rows([single, multi], expanded: []) == [.story(single.id), .story(multi.id)])
        #expect(
            KeyboardNavigation.rows([single, multi], expanded: [multi.id, single.id])
                == [.story(single.id), .story(multi.id), .article(multi.id, first.id), .article(multi.id, second.id)])
    }

    @Test func nextAndPreviousWalkTheRows() {
        #expect(action(.next, at: nil) == .select(.story(single.id)))
        #expect(action(.previous, at: nil) == .select(.story(single.id)))
        #expect(action(.next, at: .story(single.id)) == .select(.story(multi.id)))
        #expect(action(.next, at: .story(multi.id)) == .none)
        #expect(action(.previous, at: .story(single.id)) == .none)
        #expect(
            action(.next, at: .story(multi.id), expanded: [multi.id]) == .select(.article(multi.id, first.id)))
        #expect(
            action(.previous, at: .article(multi.id, first.id), expanded: [multi.id]) == .select(.story(multi.id)))
        // A cursor that is no longer in the list starts again at the top.
        #expect(action(.next, at: .story(.loose(.init()))) == .select(.story(single.id)))
        let empty = KeyboardNavigation.action(
            for: .next, at: nil, entry: nil, rows: [], expanded: [], opensInWindow: true, pageArticle: nil)
        #expect(empty == .none)
    }

    @Test func expandOpensMultiArticleStoriesOrEntersThem() {
        #expect(action(.expand, at: .story(multi.id)) == .expand(multi.id))
        #expect(action(.expand, at: .story(multi.id), expanded: [multi.id]) == .select(.article(multi.id, first.id)))
        #expect(action(.expand, at: .story(single.id)) == .none)
        #expect(action(.expand, at: .article(multi.id, first.id), expanded: [multi.id]) == .none)
        #expect(action(.expand, at: nil) == .none)
    }

    @Test func collapseAndEscapeCloseTheStory() {
        #expect(action(.collapse, at: .article(multi.id, second.id), expanded: [multi.id]) == .collapse(multi.id))
        #expect(action(.escape, at: .article(multi.id, second.id), expanded: [multi.id]) == .collapse(multi.id))
        #expect(action(.collapse, at: .story(multi.id), expanded: [multi.id]) == .collapse(multi.id))
        #expect(action(.escape, at: .story(multi.id), expanded: [multi.id]) == .collapse(multi.id))
        #expect(action(.collapse, at: .story(multi.id)) == .none)
        #expect(action(.collapse, at: .story(single.id)) == .none)
    }

    @Test func escapeLeavesTheSourcePageFirst() {
        #expect(action(.escape, at: .story(single.id), page: lone.id) == .closePage)
        #expect(
            action(.escape, at: .article(multi.id, first.id), expanded: [multi.id], page: first.id) == .closePage)
    }

    @Test func openUsesTheDefaultWayAndShiftTheOther() {
        let link = lone.link!
        #expect(action(.open, at: .story(single.id)) == .openPage(link, inWindow: true))
        #expect(action(.openOther, at: .story(single.id)) == .openPage(link, inWindow: false))
        #expect(action(.open, at: .story(single.id), opensInWindow: false) == .openPage(link, inWindow: false))
        #expect(action(.openOther, at: .story(single.id), opensInWindow: false) == .openPage(link, inWindow: true))
        #expect(
            action(.open, at: .article(multi.id, second.id), expanded: [multi.id])
                == .openPage(second.link!, inWindow: true))
    }

    @Test func openingTheShownPageInTheWindowAgainGoesBack() {
        #expect(action(.open, at: .story(single.id), page: lone.id) == .closePage)
        #expect(action(.openOther, at: .story(single.id), opensInWindow: false, page: lone.id) == .closePage)
        // The browser still opens while the page is shown.
        #expect(action(.openOther, at: .story(single.id), page: lone.id) == .openPage(lone.link!, inWindow: false))
    }

    @Test func openOnACollapsedMultiArticleStoryExpandsIt() {
        #expect(action(.open, at: .story(multi.id)) == .expand(multi.id))
        #expect(action(.open, at: .story(multi.id), expanded: [multi.id]) == .none)
        #expect(action(.openOther, at: .story(multi.id)) == .none)
    }

    @Test func openWithoutALinkDoesNothing() {
        var article = lone
        article.link = nil
        let entry = StoryEntry(id: .loose(article.id), title: "", articles: [article], newArticleIDs: [])
        let result = KeyboardNavigation.action(
            for: .open, at: .story(entry.id), entry: entry, rows: [.story(entry.id)], expanded: [],
            opensInWindow: true, pageArticle: nil)
        #expect(result == .none)
        #expect(action(.open, at: .article(multi.id, .init()), expanded: [multi.id]) == .none)
    }

    @Test func previewAndSummarizeWorkOnAnArticle() {
        #expect(action(.preview, at: .story(single.id)) == .previewPage(lone.id))
        #expect(action(.summarizePage, at: .story(single.id)) == .summarizePage(lone.id))
        #expect(
            action(.preview, at: .article(multi.id, second.id), expanded: [multi.id]) == .previewPage(second.id))
        #expect(
            action(.summarizePage, at: .article(multi.id, second.id), expanded: [multi.id])
                == .summarizePage(second.id))
        // While the source page is shown too.
        #expect(action(.summarizePage, at: .story(single.id), page: lone.id) == .summarizePage(lone.id))
    }

    @Test func previewAndSummarizeDoNothingOnAStoryWithSeveralArticles() {
        #expect(action(.preview, at: .story(multi.id)) == .none)
        #expect(action(.summarizePage, at: .story(multi.id), expanded: [multi.id]) == .none)
        #expect(action(.preview, at: nil) == .none)
    }

    @Test func previewAndSummarizeNeedALink() {
        var article = lone
        article.link = nil
        let entry = StoryEntry(id: .loose(article.id), title: "", articles: [article], newArticleIDs: [])
        for key in [ListKey.preview, .summarizePage] {
            let result = KeyboardNavigation.action(
                for: key, at: .story(entry.id), entry: entry, rows: [.story(entry.id)], expanded: [],
                opensInWindow: true, pageArticle: nil)
            #expect(result == .none)
        }
    }

    @Test func saveWithSummaryPreparesThePageOfAnArticleWithALink() {
        #expect(action(.saveWithSummary, at: .story(single.id)) == .saveWithSummary(.story(single.id), lone.id))
        #expect(
            action(.saveWithSummary, at: .article(multi.id, second.id), expanded: [multi.id])
                == .saveWithSummary(.article(multi.id, second.id), second.id))
        #expect(action(.saveWithSummary, at: .story(multi.id)) == .saveWithSummary(.story(multi.id), nil))
        var article = lone
        article.link = nil
        let entry = StoryEntry(id: .loose(article.id), title: "", articles: [article], newArticleIDs: [])
        let result = KeyboardNavigation.action(
            for: .saveWithSummary, at: .story(entry.id), entry: entry, rows: [.story(entry.id)], expanded: [],
            opensInWindow: true, pageArticle: nil)
        #expect(result == .saveWithSummary(.story(entry.id), nil))
    }

    @Test func theOtherKeysNeedNoCursor() {
        #expect(action(.toggleRead, at: .story(multi.id)) == .toggleRead(.story(multi.id)))
        #expect(action(.toggleRead, at: nil) == .none)
        #expect(action(.save, at: .story(multi.id)) == .toggleSaved(.story(multi.id)))
        #expect(
            action(.save, at: .article(multi.id, first.id), expanded: [multi.id])
                == .toggleSaved(.article(multi.id, first.id)))
        #expect(action(.save, at: nil) == .none)
        #expect(action(.saveWithSummary, at: nil) == .none)
        #expect(action(.refresh, at: nil) == .refresh)
        #expect(action(.markAllRead, at: nil) == .markAllRead)
        #expect(action(.shortcuts, at: nil) == .showShortcuts)
    }
}
