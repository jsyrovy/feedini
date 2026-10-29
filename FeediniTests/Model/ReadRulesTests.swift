import Testing

@testable import Feedini

struct ReadRulesTests {
    private let feed = Feed.stub()

    private func story(_ articles: [Article]) -> StoryEntry {
        StoryEntry(id: .story(.init()), title: "Story", articles: articles, newArticleIDs: [])
    }

    @Test func visitingACollapsedStoryReadsAllItsUnreadArticles() {
        let unread = Article.stub(feed: feed.id)
        let read = Article.stub(feed: feed.id, read: true)
        let entry = story([unread, read])

        #expect(ReadRules.articlesRead(byVisiting: .story(entry.id), of: entry, isExpanded: false) == [unread.id])
    }

    @Test func visitingAnExpandedStoryReadsNothingButItsArticlesOneByOne() {
        let first = Article.stub(feed: feed.id)
        let second = Article.stub(feed: feed.id, read: true)
        let entry = story([first, second])

        #expect(ReadRules.articlesRead(byVisiting: .story(entry.id), of: entry, isExpanded: true).isEmpty)
        #expect(
            ReadRules.articlesRead(byVisiting: .article(entry.id, first.id), of: entry, isExpanded: true) == [first.id])
        #expect(ReadRules.articlesRead(byVisiting: .article(entry.id, second.id), of: entry, isExpanded: true).isEmpty)
        #expect(ReadRules.articlesRead(byVisiting: .article(entry.id, .init()), of: entry, isExpanded: true).isEmpty)
    }

    @Test func toggleOnAStoryFlipsAllItsArticles() {
        let first = Article.stub(feed: feed.id, read: true)
        let second = Article.stub(feed: feed.id)
        let partly = story([first, second])
        #expect(ReadRules.toggle(.story(partly.id), of: partly) == .markRead([first.id, second.id]))

        let read = story([first, Article.stub(feed: feed.id, read: true)])
        #expect(ReadRules.toggle(.story(read.id), of: read) == .markUnread(read.articles.map(\.id)))
    }

    @Test func toggleOnAnArticleFlipsOnlyIt() {
        let read = Article.stub(feed: feed.id, read: true)
        let unread = Article.stub(feed: feed.id)
        let entry = story([read, unread])

        #expect(ReadRules.toggle(.article(entry.id, read.id), of: entry) == .markUnread([read.id]))
        #expect(ReadRules.toggle(.article(entry.id, unread.id), of: entry) == .markRead([unread.id]))
    }

    @Test func rowsKnowTheirEntry() {
        let id = StoryEntry.ID.loose(.init())
        #expect(ListRow.story(id).entryID == id)
        #expect(ListRow.article(id, .init()).entryID == id)
    }
}
