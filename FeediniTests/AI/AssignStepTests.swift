import Foundation
import Testing

@testable import Feedini

struct AssignStepTests {
    private let tech = Feed.stub("Tech")
    private let news = Feed.stub("News")

    @Test func theSchemaIsValidJSON() throws {
        let schema = try JSONSerialization.jsonObject(with: Data(Prompts.assignSchema.utf8)) as? [String: Any]
        #expect(schema?["required"] as? [String] == ["attach", "new_topics", "new_stories"])
        #expect(Prompts.assign.contains("never a name."))
        #expect(!Prompts.assign.contains("\\"))
    }

    @Test func buildsThePayloadWithShortIDs() throws {
        let apple = Topic(name: "Apple", description: "Apple news.")
        let stale = Topic(name: "Stale", description: "Only read stories.")
        let recent1 = Article.stub("Laptop announced", feed: tech.id, hours: -5)
        let recent2 = Article.stub("Laptop price", feed: news.id, hours: -4, read: true)
        let readRecent = Article.stub("Read recent", feed: tech.id, hours: -10, read: true)
        let old = Article.stub("Old", feed: tech.id, hours: -80)
        let laptop = Story(title: "Laptop", topicID: apple.id, articleIDs: [recent1.id, recent2.id])
        let readStory = Story(title: "Read story", topicID: stale.id, articleIDs: [readRecent.id])
        let oldStory = Story(title: "Old story", topicID: apple.id, articleIDs: [old.id])
        var new = Article.stub("New <article>", feed: news.id, hours: 0)
        new.text = String(repeating: "word ", count: 200)
        new.published = Date(timeIntervalSince1970: 1_793_275_200)
        let library = Library(
            feeds: [tech, news], articles: [recent1, recent2, readRecent, old, new],
            stories: [laptop, readStory, oldStory], topics: [apple, stale])

        let (input, map) = AssignStep.payload(for: [new.id], in: library, language: "Czech", now: referenceDate)

        #expect(input.outputLanguage == "Czech")
        // Topics of unread stories only; the old story is unread too.
        #expect(input.topics == [.init(id: "t1", name: "Apple", description: "Apple news.")])
        // Stories in the attach window, newest first, read ones included.
        #expect(input.stories.map(\.title) == ["Laptop", "Read recent"])
        #expect(input.stories[0].topicID == "t1")
        #expect(input.stories[1].topicID == nil)
        #expect(
            input.stories[0].articles == [
                .init(source: "Tech", title: "Laptop announced"), .init(source: "News", title: "Laptop price"),
            ])
        let item = try #require(input.newArticles.first)
        #expect(item.id == "a1")
        #expect(item.source == "News")
        #expect(item.title == "New <article>")
        #expect(item.published == "2026-10-29T12:00:00Z")
        #expect(item.description.count <= AssignStep.excerptLength + 1)
        #expect(item.description.hasSuffix("…"))
        #expect(map.articles == ["a1": new.id])
        #expect(map.stories == ["s1": laptop.id, "s2": readStory.id])
        #expect(map.topics == ["t1": apple.id])
    }

    @Test func encodesTheKeysThePromptDescribes() throws {
        let feed = Feed.stub("Tech")
        let article = Article.stub("A", feed: feed.id)
        let library = Library(feeds: [feed], articles: [article])
        let (input, _) = AssignStep.payload(
            for: [article.id, UUID()], in: library, language: "English", now: referenceDate)

        let request = ClaudeRequest(
            model: "claude-haiku-5-5", effort: "low", systemPrompt: Prompts.assign, schema: Prompts.assignSchema,
            payload: input)

        #expect(request.model == "claude-haiku-5-5")
        #expect(request.effort == "low")
        #expect(request.systemPrompt == Prompts.assign)
        #expect(request.schema == Prompts.assignSchema)
        let json = try #require(JSONSerialization.jsonObject(with: request.input) as? [String: Any])
        #expect(Set(json.keys) == ["output_language", "topics", "stories", "new_articles"])
        let articles = try #require(json["new_articles"] as? [[String: Any]])
        #expect(articles.count == 1)
        #expect(Set(articles[0].keys) == ["id", "source", "title", "published", "description"])
    }

    @Test func decodesTheAnswer() throws {
        let json = """
            {"attach":[{"story_id":"s1","article_ids":["a1"]}],
             "new_topics":[{"key":"n1","name":"Games","description":"Video games."}],
             "new_stories":[{"title":"T","topic":"n1","article_ids":["a2","a3"]}]}
            """
        let output = try JSONDecoder().decode(AssignStep.Output.self, from: Data(json.utf8))
        #expect(output.attach == [.init(storyID: "s1", articleIDs: ["a1"])])
        #expect(output.newTopics == [.init(key: "n1", name: "Games", description: "Video games.")])
        #expect(output.newStories == [.init(title: "T", topic: "n1", articleIDs: ["a2", "a3"])])
    }
}
