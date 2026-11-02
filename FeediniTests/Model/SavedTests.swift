import Foundation
import Testing

@testable import Feedini

struct SavedTests {
    private let feed = Feed.stub("Tech")
    private let other = Feed.stub("News")

    @Test func savesAndUnsavesArticlesAndStories() {
        let article = Article.stub(feed: feed.id)
        let story = Story(title: "Story", articleIDs: [article.id])
        var library = Library(feeds: [feed], articles: [article], stories: [story])

        library.setSaved(.article(article.id), at: .hours(1))
        library.setSaved(.story(story.id), at: .hours(2))
        #expect(library.articles[article.id]?.savedAt == .hours(1))
        #expect(library.articles[article.id]?.isSaved == true)
        #expect(library.stories[story.id]?.savedAt == .hours(2))

        library.setSaved(.article(article.id), at: nil)
        library.setSaved(.story(story.id), at: nil)
        #expect(library.articles[article.id]?.savedAt == nil)
        #expect(library.stories[story.id]?.savedAt == nil)
    }

    @Test func unknownItemsAreNotSaved() {
        var library = Library(feeds: [feed], articles: [])
        library.setSaved(.article(UUID()), at: .hours(1))
        library.setSaved(.story(UUID()), at: .hours(1))
        #expect(library == Library(feeds: [feed], articles: []))
    }

    @Test func savingKeepsSavedArticlesAndAllArticlesOfSavedStories() {
        let saved = Article.stub(feed: feed.id, savedAt: .hours(1))
        let first = Article.stub(feed: feed.id)
        let second = Article.stub(feed: other.id)
        let loose = Article.stub(feed: feed.id)
        let story = Story(title: "Story", articleIDs: [first.id, second.id], savedAt: .hours(1))
        let library = Library(feeds: [feed, other], articles: [saved, first, second, loose], stories: [story])

        #expect(library.articleIDsKeptBySaving() == [saved.id, first.id, second.id])
    }

    @Test func removingAFeedKeepsWhatSavingKeepsWithTheFeedName() {
        let saved = Article.stub(feed: feed.id, savedAt: .hours(1))
        let inSavedStory = Article.stub(feed: feed.id)
        let theirs = Article.stub(feed: other.id)
        let gone = Article.stub(feed: feed.id)
        let story = Story(title: "Story", articleIDs: [inSavedStory.id, theirs.id], savedAt: .hours(1))
        var library = Library(
            feeds: [feed, other], articles: [saved, inSavedStory, theirs, gone], stories: [story])

        library.removeFeed(feed.id)

        #expect(library.feeds == [other])
        #expect(Set(library.articles.keys) == [saved.id, inSavedStory.id, theirs.id])
        #expect(library.stories[story.id]?.articleIDs == [inSavedStory.id, theirs.id])
        #expect(library.removedFeeds == [feed.id: "Tech"])
        #expect(library.sourceTitle(of: feed.id) == "Tech")
        #expect(library.sourceTitle(of: other.id) == "News")
        #expect(library.sourceTitle(of: UUID()) == nil)
        #expect(library.sourceTitles() == [feed.id: "Tech", other.id: "News"])
    }

    @Test func countsTheArticlesOfFeedsThatSavingKeeps() {
        let saved = Article.stub(feed: feed.id, savedAt: .hours(1))
        let inSavedStory = Article.stub(feed: other.id)
        let story = Story(title: "Story", articleIDs: [inSavedStory.id, UUID()], savedAt: .hours(1))
        let library = Library(
            feeds: [feed, other], articles: [saved, inSavedStory, Article.stub(feed: feed.id)], stories: [story])

        #expect(library.savedArticleCount(of: [feed.id]) == 1)
        #expect(library.savedArticleCount(of: [feed.id, other.id]) == 2)
        #expect(library.savedArticleCount(of: []) == 0)
    }

    @Test func removingAFeedWithoutSavedArticlesForgetsItsName() {
        var library = Library(feeds: [feed], articles: [Article.stub(feed: feed.id)])
        library.removeFeed(feed.id)
        #expect(library.articles.isEmpty)
        #expect(library.removedFeeds.isEmpty)
    }

    @Test func codableRoundTripKeepsSavingAndRemovedFeeds() throws {
        let article = Article.stub(feed: feed.id, savedAt: .hours(1))
        let story = Story(title: "Story", articleIDs: [article.id], savedAt: .hours(2))
        var library = Library(feeds: [], articles: [article], stories: [story])
        library.removedFeeds = [feed.id: "Tech", other.id: "News"]

        let decoded = try LibraryStore.decoder.decode(Library.self, from: LibraryStore.encoder.encode(library))

        #expect(decoded == library)
    }

    @Test func olderFilesLoadWithoutSavingOrRemovedFeeds() throws {
        let json = """
            {"feeds": [], "articles": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
              "feedID": "7F9619FF-8B86-D011-B42D-00C04FC964FF", "key": "k", "title": "T", "text": "",
              "firstSeen": "2026-10-29T12:00:00Z"}],
             "stories": [{"id": "8F9619FF-8B86-D011-B42D-00C04FC964FF", "title": "S",
              "articleIDs": ["6F9619FF-8B86-D011-B42D-00C04FC964FF"], "newArticleIDs": []}],
             "topics": [], "tombstones": []}
            """
        let library = try LibraryStore.decoder.decode(Library.self, from: Data(json.utf8))

        #expect(library.articles.values.allSatisfy { !$0.isSaved })
        #expect(library.stories.values.allSatisfy { $0.savedAt == nil })
        #expect(library.removedFeeds.isEmpty)
    }
}
