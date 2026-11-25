import Testing

@testable import Feedini

struct ReadRulesTests {
    private let feed = Feed.stub()

    private func story(_ articles: [Article]) -> StoryEntry {
        StoryEntry(id: .story(.init()), title: "Story", articles: articles)
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

    @Test func aStoryRowsNeighborsAreTheEntriesNextToIt() {
        let entries = [story([.stub(feed: feed.id)]), story([.stub(feed: feed.id)]), story([.stub(feed: feed.id)])]
        let middle = ListRow.story(entries[1].id)

        #expect(middle.neighbor(1, in: entries) == .story(entries[2].id))
        #expect(middle.neighbor(-1, in: entries) == .story(entries[0].id))
        #expect(ListRow.story(entries[2].id).neighbor(1, in: entries) == nil)
        #expect(ListRow.story(entries[0].id).neighbor(-1, in: entries) == nil)
        #expect(ListRow.story(.loose(.init())).neighbor(1, in: entries) == nil)
    }

    @Test func anArticleRowsNeighborsAreTheArticlesOfItsStory() {
        let first = Article.stub(feed: feed.id)
        let second = Article.stub(feed: feed.id)
        let entry = story([first, second])
        let entries = [story([.stub(feed: feed.id)]), entry]

        #expect(ListRow.article(entry.id, first.id).neighbor(1, in: entries) == .article(entry.id, second.id))
        #expect(ListRow.article(entry.id, second.id).neighbor(-1, in: entries) == .article(entry.id, first.id))
        #expect(ListRow.article(entry.id, second.id).neighbor(1, in: entries) == nil)
        #expect(ListRow.article(entry.id, first.id).neighbor(-1, in: entries) == nil)
        #expect(ListRow.article(entry.id, .init()).neighbor(1, in: entries) == nil)
        #expect(ListRow.article(.loose(.init()), first.id).neighbor(1, in: entries) == nil)
    }

    @Test func rowsKnowTheirEntry() {
        let id = StoryEntry.ID.loose(.init())
        #expect(ListRow.story(id).entryID == id)
        #expect(ListRow.article(id, .init()).entryID == id)
    }
}
