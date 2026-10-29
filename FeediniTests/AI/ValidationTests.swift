import Foundation
import Testing

@testable import Feedini

struct ValidationTests {
    private let feed = Feed.stub("Tech")
    private let apple = Topic(name: "Apple", description: "Apple news.")
    private let existing: Article
    private let story: Story
    private let new: [Article]

    init() {
        existing = Article.stub("Existing", feed: feed.id, hours: -5)
        story = Story(title: "Laptop", topicID: apple.id, articleIDs: [existing.id])
        let feedID = feed.id
        new = (1...4).map { Article.stub("New \($0)", feed: feedID, hours: Double($0)) }
    }

    private var library: Library {
        Library(feeds: [feed], articles: [existing] + new, stories: [story], topics: [apple])
    }

    private var map: AssignStep.IDMap {
        AssignStep.IDMap(
            articles: Dictionary(uniqueKeysWithValues: new.enumerated().map { ("a\($0.offset + 1)", $0.element.id) }),
            stories: ["s1": story.id], topics: ["t1": apple.id])
    }

    private func output(
        attach: [AssignStep.Output.Attachment] = [], topics: [AssignStep.Output.NewTopic] = [],
        stories: [AssignStep.Output.NewStory] = []
    ) -> AssignStep.Output {
        AssignStep.Output(attach: attach, newTopics: topics, newStories: stories)
    }

    private func storyOf(_ article: Article, in library: Library) -> Story? {
        library.stories.values.first { $0.articleIDs.contains(article.id) }
    }

    @Test func attachesAndCreatesStoriesWithTopics() throws {
        var library = library
        let metrics = AssignValidation.apply(
            output(
                attach: [.init(storyID: "s1", articleIDs: ["a1"])],
                topics: [.init(key: "n1", name: "Games", description: "Video games.")],
                stories: [
                    .init(title: "Game launch", topic: "n1", articleIDs: ["a2", "a3"]),
                    .init(title: "iPad", topic: "t1", articleIDs: ["a4"]),
                ]), map: map, language: "en", to: &library)

        #expect(library.stories[story.id]?.articleIDs == [existing.id, new[0].id])
        #expect(library.stories[story.id]?.newArticleIDs == [])
        let games = try #require(library.topics.values.first { $0.name == "Games" })
        #expect(games.description == "Video games.")
        let launch = try #require(storyOf(new[1], in: library))
        #expect(launch.title == "Game launch")
        #expect(launch.articleIDs == [new[1].id, new[2].id])
        #expect(launch.topicID == games.id)
        #expect(storyOf(new[3], in: library)?.topicID == apple.id)
        #expect(
            metrics
                == .init(attached: 1, newStories: 2, newTopics: 1, missing: 0, unknownIDs: 0, unresolvedTopics: 0))
    }

    @Test func dropsUnknownAndDuplicateIDs() {
        var library = library
        let metrics = AssignValidation.apply(
            output(
                attach: [
                    .init(storyID: "s1", articleIDs: ["a1", "a99", "a1"]),
                    .init(storyID: "s9", articleIDs: ["a2"]),
                ],
                stories: [
                    .init(title: "Dup", topic: "t1", articleIDs: ["a1", "a2"]),
                    .init(title: "Nothing valid", topic: "t1", articleIDs: ["x"]),
                ]), map: map, language: "en", to: &library)

        #expect(storyOf(new[0], in: library)?.id == story.id)
        #expect(storyOf(new[1], in: library)?.title == "Dup")
        #expect(storyOf(new[1], in: library)?.articleIDs == [new[1].id])
        #expect(!library.stories.values.contains { $0.title == "Nothing valid" })
        // a99, the second a1, a2 for s9, a1 in "Dup", x.
        #expect(metrics.unknownIDs == 5)
    }

    @Test func leftOutArticlesGetAStoryOfTheirOwn() {
        var library = library
        let metrics = AssignValidation.apply(
            output(stories: [.init(title: "One", topic: "t1", articleIDs: ["a2"])]), map: map, language: "en",
            to: &library)

        #expect(metrics.missing == 3)
        for article in [new[0], new[2], new[3]] {
            let own = storyOf(article, in: library)
            #expect(own?.articleIDs == [article.id])
            #expect(own?.title == article.title)
            #expect(own?.topicID == nil)
        }
        // Every new article belongs to a story now.
        #expect(Set(library.storyIDsByArticle().keys) == Set(library.articles.keys))
    }

    @Test func resolvesTopicsByNameWhenTheModelWritesNames() throws {
        var library = library
        let metrics = AssignValidation.apply(
            output(
                topics: [.init(key: "n1", name: "Games", description: "")],
                stories: [
                    .init(title: "By existing name", topic: "apple", articleIDs: ["a1"]),
                    .init(title: "By new name", topic: "Games", articleIDs: ["a2"]),
                    .init(title: "Unknown", topic: "Science", articleIDs: ["a3"]),
                    .init(title: "Empty", topic: "", articleIDs: ["a4"]),
                ]), map: map, language: "en", to: &library)

        #expect(storyOf(new[0], in: library)?.topicID == apple.id)
        let games = try #require(library.topics.values.first { $0.name == "Games" })
        #expect(storyOf(new[1], in: library)?.topicID == games.id)
        let science = try #require(library.topics.values.first { $0.name == "Science" })
        #expect(storyOf(new[2], in: library)?.topicID == science.id)
        #expect(storyOf(new[3], in: library)?.topicID == nil)
        #expect(metrics.unresolvedTopics == 3)
        #expect(metrics.newTopics == 2)
    }

    @Test func aNewTopicWithAnExistingNameReusesIt() {
        var library = library
        AssignValidation.apply(
            output(
                topics: [
                    .init(key: "n1", name: " APPLE ", description: "Dup"),
                    .init(key: "n1", name: "Other", description: ""),
                    .init(key: "n2", name: " ", description: ""),
                ],
                stories: [.init(title: "S", topic: "n1", articleIDs: ["a1"])]), map: map, language: "en", to: &library)

        #expect(library.topics.count == 1)
        #expect(storyOf(new[0], in: library)?.topicID == apple.id)
    }

    @Test func anArticleJoiningAReadStoryIsMarkedNew() {
        var library = library
        library.markRead([existing.id], at: .hours(0))

        AssignValidation.apply(
            output(attach: [.init(storyID: "s1", articleIDs: ["a1", "a2"])]), map: map, language: "en", to: &library)

        #expect(library.stories[story.id]?.newArticleIDs == [new[0].id, new[1].id])
        // The story is unread again.
        let entry = StoryList.allEntries(in: library, summaryLanguage: "en").first { $0.id == .story(story.id) }
        #expect(entry?.isRead == false)
    }

    @Test func anUntitledStoryUsesItsFirstArticle() {
        var library = library
        AssignValidation.apply(
            output(stories: [.init(title: "  ", topic: "t1", articleIDs: ["a3", "a4"])]), map: map, language: "en",
            to: &library)
        #expect(storyOf(new[2], in: library)?.title == "New 3")
    }

    @Test func ignoresArticlesThatWereRemovedMeanwhile() {
        var library = library
        library.articles[new[0].id] = nil
        let metrics = AssignValidation.apply(
            output(stories: [.init(title: "S", topic: "t1", articleIDs: ["a1", "a2"])]), map: map, language: "en",
            to: &library)

        #expect(storyOf(new[1], in: library)?.articleIDs == [new[1].id])
        #expect(metrics.unknownIDs == 1)
        #expect(metrics.missing == 2)
    }

    @Test func newTopicsGetTheOutputLanguage() throws {
        var library = library
        AssignValidation.apply(
            output(
                topics: [.init(key: "n1", name: "Hry", description: "")],
                stories: [
                    .init(title: "S", topic: "n1", articleIDs: ["a1"]),
                    .init(title: "T", topic: "Věda", articleIDs: ["a2"]),
                ]), map: map, language: "cs", to: &library)

        #expect(library.topics.values.filter { $0.id != apple.id }.allSatisfy { $0.language == "cs" })
        #expect(library.topics.count == 3)
    }
}
