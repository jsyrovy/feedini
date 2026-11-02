import Foundation
import Testing

@testable import Feedini

struct StoryListSavedTests {
    private let tech = Feed.stub("Tech")
    private let news = Feed.stub("News")

    private func saved(_ article: Article, hours: Double) -> Article {
        var article = article
        article.savedAt = .hours(hours)
        return article
    }

    private func savedEntries(_ library: Library, keeping: [StoryEntry.ID: Date] = [:]) -> [StoryEntry] {
        let all = StoryList.allEntries(in: library, summaryLanguage: "en", singleArticles: .always)
        return StoryList.savedEntries(in: library, entry: { id in all.first { $0.id == id } }, keeping: keeping)
    }

    @Test func savedEntriesAreOrderedBySaveTimeWhateverTheirReadState() {
        let loose = saved(Article.stub("Loose", feed: tech.id, hours: -50, read: true), hours: -1)
        let first = Article.stub("First", feed: tech.id, hours: -2)
        let second = Article.stub("Second", feed: news.id, hours: -3, read: true)
        let story = Story(title: "Story", articleIDs: [first.id, second.id], savedAt: .hours(-2))
        let notSaved = Article.stub("Not saved", feed: tech.id)
        let library = Library(
            feeds: [tech, news], articles: [loose, first, second, notSaved], stories: [story])

        let entries = savedEntries(library)

        #expect(entries.map(\.id) == [.savedArticle(loose.id), .story(story.id)])
        #expect(entries[0].savedAt(at: .story(entries[0].id)) == .hours(-1))
        #expect(entries[1].savedAt(at: .story(entries[1].id)) == .hours(-2))
        #expect(entries[1].storySavedAt == .hours(-2))
    }

    @Test func aSavedArticleOfAStoryWithSeveralArticlesShowsOnItsOwnWithTheStory() {
        let first = saved(Article.stub("First", feed: tech.id, hours: -2), hours: -1)
        let second = Article.stub("Second", feed: news.id, hours: -3)
        let topic = Topic(name: "Apple", description: "")
        let story = Story(title: "Story", topicID: topic.id, articleIDs: [first.id, second.id])
        let library = Library(feeds: [tech, news], articles: [first, second], stories: [story], topics: [topic])

        let entry = savedEntries(library)[0]

        #expect(entry.id == .savedArticle(first.id))
        #expect(entry.title == "First")
        #expect(entry.articles == [first])
        #expect(entry.partOf == "Story")
        #expect(entry.topicID == topic.id)
        #expect(!entry.isMultiArticle)
        #expect(entry.savedItem(at: .story(entry.id)) == .article(first.id))
    }

    @Test func aSavedArticleOfAOneArticleStoryTakesItsSummary() {
        let article = saved(Article.stub("Article", feed: tech.id, language: "cs"), hours: -1)
        let summary = Summary(title: "Summary title", text: "Gist.", language: "en", articleIDs: [article.id])
        let story = Story(title: "Story", articleIDs: [article.id], summary: summary)
        let library = Library(feeds: [tech], articles: [article], stories: [story])

        let entry = savedEntries(library)[0]

        #expect(entry.id == .savedArticle(article.id))
        #expect(entry.title == "Summary title")
        #expect(entry.needsSummary)
        #expect(entry.summary == summary)
        #expect(entry.isSummaryCurrent)
        #expect(entry.partOf == nil)
    }

    @Test func keptEntriesStayInTheirPlaceAfterTheyAreRemovedFromSaved() {
        let newer = saved(Article.stub("Newer", feed: tech.id), hours: -1)
        let removed = Article.stub("Removed", feed: tech.id)
        let older = saved(Article.stub("Older", feed: tech.id), hours: -3)
        let first = Article.stub("First", feed: tech.id)
        let second = Article.stub("Second", feed: tech.id)
        let story = Story(title: "Story", articleIDs: [first.id, second.id])
        let library = Library(feeds: [tech], articles: [newer, removed, older, first, second], stories: [story])

        let entries = savedEntries(
            library, keeping: [.savedArticle(removed.id): .hours(-2), .story(story.id): .hours(-4)])

        #expect(
            entries.map(\.id) == [
                .savedArticle(newer.id), .savedArticle(removed.id), .savedArticle(older.id), .story(story.id),
            ])
        #expect(entries[1].savedAt(at: .story(entries[1].id)) == nil)
    }

    @Test func theStoryRowSavesTheStoryWithSeveralArticlesElseItsArticle() {
        let first = Article.stub("First", feed: tech.id)
        let second = Article.stub("Second", feed: tech.id)
        let storyID = Story.ID()
        let multi = StoryEntry(id: .story(storyID), title: "", articles: [first, second], newArticleIDs: [])
        let single = StoryEntry(id: .story(storyID), title: "", articles: [first], newArticleIDs: [])
        var savedSingle = single
        savedSingle.storySavedAt = .hours(1)
        let loose = StoryEntry(id: .loose(first.id), title: "", articles: [first], newArticleIDs: [])
        let empty = StoryEntry(id: .loose(first.id), title: "", articles: [], newArticleIDs: [])

        #expect(multi.savedItem(at: .story(multi.id)) == .story(storyID))
        #expect(multi.savedItem(at: .article(multi.id, second.id)) == .article(second.id))
        #expect(single.savedItem(at: .story(single.id)) == .article(first.id))
        #expect(savedSingle.savedItem(at: .story(single.id)) == .story(storyID))
        #expect(savedSingle.savedAt(at: .story(single.id)) == .hours(1))
        #expect(loose.savedItem(at: .story(loose.id)) == .article(first.id))
        #expect(empty.savedItem(at: .story(empty.id)) == nil)
        #expect(empty.savedAt(at: .story(empty.id)) == nil)
    }

    @Test func savedIsNotAFilterOfAllAndCountsEverySavedEntry() {
        let article = Article.stub("Article", feed: tech.id)
        let entry = StoryList.entry(for: article)

        #expect(!StoryList.matches(entry, .saved, folders: [:]))
        #expect(StoryList.entries([entry], matching: .saved, folders: [:]).isEmpty)
        let counts = StoryList.unreadCounts([entry], saved: 3, folders: [:])
        #expect(counts.count(for: .saved) == 3)
        #expect(counts.all == 1)
        #expect(Library().contains(.saved))
    }
}
