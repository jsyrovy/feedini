import Foundation
import Testing

@testable import Feedini

struct StoryListTests {
    private let tech = Feed.stub("Tech")
    private let news = Feed.stub("News")

    @Test func listsStoriesAndLooseArticlesNewestFirst() {
        let older = Article.stub("B older", feed: tech.id, hours: -5)
        let inStory1 = Article.stub("Story part 1", feed: tech.id, hours: -3)
        let inStory2 = Article.stub("Story part 2", feed: news.id, hours: -1)
        let tieA = Article.stub("A tie", feed: news.id, hours: -4)
        let tieB = Article.stub("b tie", feed: news.id, hours: -4)
        let topic = Topic(name: "Apple", description: "")
        let story = Story(title: "The story", topicID: topic.id, articleIDs: [inStory1.id, inStory2.id])
        let library = Library(
            feeds: [tech, news], articles: [older, inStory1, inStory2, tieA, tieB], stories: [story], topics: [topic])

        let entries = StoryList.allEntries(in: library)

        #expect(
            entries.map(\.id) == [.story(story.id), .loose(tieA.id), .loose(tieB.id), .loose(older.id)])
        let first = entries[0]
        #expect(first.title == "The story")
        #expect(first.topicID == topic.id)
        #expect(first.articles.map(\.id) == [inStory2.id, inStory1.id])
        #expect(first.date == .hours(-1))
        #expect(first.isMultiArticle)
        #expect(first.feedIDs == [news.id, tech.id])
        #expect(first.article(inStory1.id) == inStory1)
        #expect(first.article(older.id) == nil)
        #expect(entries[3].title == "B older")
        #expect(!entries[3].isMultiArticle)
    }

    @Test func aStoryWithOneArticleUsesTheArticleTitleAndEmptyStoriesAreSkipped() {
        let article = Article.stub("Article title", feed: tech.id)
        let single = Story(title: "AI title", articleIDs: [article.id])
        let empty = Story(title: "Empty", articleIDs: [UUID()])
        let library = Library(feeds: [tech], articles: [article], stories: [single, empty])

        let entries = StoryList.allEntries(in: library)

        #expect(entries.map(\.id) == [.story(single.id)])
        #expect(entries[0].title == "Article title")
    }

    @Test func filtersBySelectionAndHidesReadEntriesUnlessKept() {
        let topic = Topic(name: "Apple", description: "")
        let unread = Article.stub("Unread", feed: tech.id, hours: -1)
        let read = Article.stub("Read", feed: tech.id, hours: -2, read: true)
        let keptRead = Article.stub("Kept", feed: news.id, hours: -3, read: true)
        let mixedTech = Article.stub("Mixed tech", feed: tech.id, hours: -4, read: true)
        let mixedNews = Article.stub("Mixed news", feed: news.id, hours: -4)
        let mixed = Story(title: "Mixed", topicID: topic.id, articleIDs: [mixedTech.id, mixedNews.id])
        let library = Library(
            feeds: [tech, news], articles: [unread, read, keptRead, mixedTech, mixedNews], stories: [mixed],
            topics: [topic])
        let all = StoryList.allEntries(in: library)
        let keeping: Set<StoryEntry.ID> = [.loose(keptRead.id)]

        #expect(StoryList.entries(all, matching: .all).map(\.title) == ["Unread", "Mixed"])
        #expect(StoryList.entries(all, matching: .all, keeping: keeping).map(\.title) == ["Unread", "Kept", "Mixed"])
        // A story shows in every feed it has an article of.
        #expect(StoryList.entries(all, matching: .feed(tech.id)).map(\.title) == ["Unread", "Mixed"])
        #expect(StoryList.entries(all, matching: .feed(news.id), keeping: keeping).map(\.title) == ["Kept", "Mixed"])
        #expect(StoryList.entries(all, matching: .topic(topic.id)).map(\.title) == ["Mixed"])
        #expect(StoryList.entries(all, matching: .topic(UUID())).isEmpty)
    }

    @Test func countsUnreadEntriesPerSidebarItem() {
        let apple = Topic(name: "Apple", description: "")
        let games = Topic(name: "Games", description: "")
        let empty = Topic(name: "Empty", description: "")
        let a1 = Article.stub(feed: tech.id)
        let a2 = Article.stub(feed: news.id, read: true)
        let a3 = Article.stub(feed: news.id)
        let a4 = Article.stub(feed: tech.id)
        let readOnly = Article.stub(feed: tech.id, read: true)
        let both = Story(title: "Both", topicID: apple.id, articleIDs: [a1.id, a2.id])
        let gamesStory1 = Story(title: "G1", topicID: games.id, articleIDs: [a3.id])
        let gamesStory2 = Story(title: "G2", topicID: games.id, articleIDs: [a4.id])
        let readStory = Story(title: "Read", topicID: empty.id, articleIDs: [readOnly.id])
        let loose = Article.stub(feed: news.id)
        let library = Library(
            feeds: [tech, news], articles: [a1, a2, a3, a4, readOnly, loose],
            stories: [both, gamesStory1, gamesStory2, readStory], topics: [apple, games, empty])

        let counts = StoryList.unreadCounts(StoryList.allEntries(in: library))

        #expect(counts.all == 4)
        #expect(counts.count(for: .all) == 4)
        #expect(counts.count(for: .topic(apple.id)) == 1)
        #expect(counts.count(for: .topic(games.id)) == 2)
        #expect(counts.count(for: .topic(empty.id)) == 0)
        #expect(counts.count(for: .feed(tech.id)) == 2)
        #expect(counts.count(for: .feed(news.id)) == 3)
        #expect(StoryList.topics(in: library, counts: counts).map(\.name) == ["Games", "Apple"])
    }

    @Test func topicsWithTheSameCountAreSortedByName() {
        let b = Topic(name: "b", description: "")
        let a = Topic(name: "A", description: "")
        let first = Article.stub(feed: tech.id)
        let second = Article.stub(feed: tech.id)
        let library = Library(
            feeds: [tech], articles: [first, second],
            stories: [
                Story(title: "1", topicID: b.id, articleIDs: [first.id]),
                Story(title: "2", topicID: a.id, articleIDs: [second.id]),
            ], topics: [b, a])
        let counts = StoryList.unreadCounts(StoryList.allEntries(in: library))
        #expect(StoryList.topics(in: library, counts: counts).map(\.name) == ["A", "b"])
    }
}
