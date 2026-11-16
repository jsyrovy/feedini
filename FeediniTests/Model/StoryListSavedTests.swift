import Foundation
import Testing

@testable import Feedini

struct StoryListSavedTests {
    private let tech = Feed.stub("Tech")
    private let news = Feed.stub("News")

    @Test func savedEntriesAreSavedArticlesOrderedBySaveTimeWhateverTheirReadState() {
        let loose = Article.stub("Loose", feed: tech.id, hours: -50, read: true, savedAt: .hours(-1))
        let first = Article.stub("First", feed: tech.id, hours: -2, savedAt: .hours(-2))
        let second = Article.stub("Second", feed: news.id, hours: -3, read: true)
        let story = Story(title: "Story", articleIDs: [first.id, second.id])
        let notSaved = Article.stub("Not saved", feed: tech.id)
        let library = Library(
            feeds: [tech, news], articles: [loose, first, second, notSaved], stories: [story])

        let entries = StoryList.savedEntries(in: library)

        #expect(entries.map(\.id) == [.savedArticle(loose.id), .savedArticle(first.id)])
        #expect(entries.map { $0.articles.first?.savedAt } == [.hours(-1), .hours(-2)])
    }

    @Test func aSavedArticleShowsOnItsOwnWithoutItsStory() {
        let first = Article.stub("First", feed: tech.id, hours: -2, language: "cs", savedAt: .hours(-1))
        let second = Article.stub("Second", feed: news.id, hours: -3)
        let topic = Topic(name: "Apple", description: "")
        let summary = Summary(title: "Summary title", text: "Gist.", language: "en", articleIDs: [first.id])
        let story = Story(title: "Story", topicID: topic.id, articleIDs: [first.id], summary: summary)
        let multi = Story(title: "Multi", articleIDs: [second.id])
        let library = Library(
            feeds: [tech, news], articles: [first, second], stories: [story, multi], topics: [topic])

        let entry = StoryList.savedEntries(in: library)[0]

        #expect(entry.id == .savedArticle(first.id))
        #expect(entry.title == "First")
        #expect(entry.articles == [first])
        #expect(entry.topicID == nil)
        #expect(!entry.needsSummary)
        #expect(entry.summary == nil)
        #expect(!entry.isMultiArticle)
        #expect(entry.singleArticle(at: .story(entry.id)) == first)
    }

    @Test func keptEntriesStayInTheirPlaceAfterTheyAreRemovedFromSaved() {
        let newer = Article.stub("Newer", feed: tech.id, savedAt: .hours(-1))
        let removed = Article.stub("Removed", feed: tech.id)
        let older = Article.stub("Older", feed: tech.id, savedAt: .hours(-3))
        let library = Library(feeds: [tech], articles: [newer, removed, older])

        let entries = StoryList.savedEntries(
            StoryList.savedEntries(in: library), keeping: [(.hours(-2), StoryList.savedEntry(for: removed))])

        #expect(entries.map(\.id) == [.savedArticle(newer.id), .savedArticle(removed.id), .savedArticle(older.id)])
        #expect(entries[1].articles.first?.isSaved == false)
    }

    @Test func onlyRowsWithASingleArticleAreSavedAndAStoryShowsItsSavedArticles() {
        let first = Article.stub("First", feed: tech.id)
        let second = Article.stub("Second", feed: tech.id, savedAt: .hours(1))
        let storyID = Story.ID()
        let multi = StoryEntry(id: .story(storyID), title: "", articles: [first, second])
        let single = StoryEntry(id: .story(storyID), title: "", articles: [second])
        let loose = StoryEntry(id: .loose(first.id), title: "", articles: [first])
        let empty = StoryEntry(id: .loose(first.id), title: "", articles: [])

        #expect(multi.singleArticle(at: .story(multi.id)) == nil)
        #expect(multi.singleArticle(at: .article(multi.id, second.id)) == second)
        #expect(multi.containsSaved)
        #expect(single.singleArticle(at: .story(single.id)) == second)
        #expect(loose.singleArticle(at: .story(loose.id)) == first)
        #expect(!loose.containsSaved)
        #expect(empty.singleArticle(at: .story(empty.id)) == nil)
    }

    @Test func savedIsNotAFilterOfAllAndCountsEverySavedEntry() {
        let article = Article.stub("Article", feed: tech.id)
        let entry = StoryList.entry(for: article)

        #expect(!StoryList.matches(entry, .saved, folders: [:]))
        #expect(StoryList.entries([entry], matching: .saved, folders: [:]).isEmpty)
        #expect(StoryList.Counts(saved: 3).count(for: .saved) == 3)
        #expect(Library().contains(.saved))
    }
}
