import Foundation
import Testing

@testable import Feedini

struct SummaryStepTests {
    private let tech = Feed.stub("Tech")
    private let news = Feed.stub("News")

    private func article(
        _ title: String, feed: Feed, hours: Double = 0, language: String? = "cs", read: Bool = false
    )
        -> Article
    {
        var article = Article.stub(title, feed: feed.id, hours: hours, read: read)
        article.language = language
        return article
    }

    @Test func theSchemasAreValidJSON() throws {
        for schema in [Prompts.summarySchema, Prompts.translateTopicsSchema] {
            #expect(try JSONSerialization.jsonObject(with: Data(schema.utf8)) is [String: Any])
        }
        #expect(Prompts.summary.contains("starting with \"- \""))
    }

    @Test func storiesNeedASummaryWithSeveralArticlesOrAnotherLanguage() {
        let czech = article("A", feed: tech)
        let english = article("B", feed: tech, language: "en")
        let unknown = article("C", feed: tech, language: nil)
        #expect(!SummaryStep.needsSummary([czech], language: "cs"))
        #expect(!SummaryStep.needsSummary([unknown], language: "cs"))
        #expect(SummaryStep.needsSummary([english], language: "cs"))
        #expect(SummaryStep.needsSummary([czech, unknown], language: "cs"))
        #expect(!SummaryStep.needsSummary([english], language: "en"))
    }

    @Test func aSummaryIsCurrentForTheSameArticlesAndLanguage() {
        let a = UUID()
        let b = UUID()
        let story = Story(title: "S", articleIDs: [a, b])
        let summary = Summary(title: "T", text: "X", language: "cs", articleIDs: [b, a])
        #expect(SummaryStep.isCurrent(summary, of: story, language: "cs"))
        #expect(!SummaryStep.isCurrent(summary, of: story, language: "en"))
        #expect(!SummaryStep.isCurrent(nil, of: story, language: "cs"))
        var grown = story
        grown.articleIDs.append(UUID())
        #expect(!SummaryStep.isCurrent(summary, of: grown, language: "cs"))
    }

    @Test func pendingStoriesAreUnreadOnesWithoutACurrentSummaryByPriority() {
        let s1a = article("Same feed 1", feed: tech, hours: -1)
        let s1b = article("Same feed 2", feed: tech, hours: -1)
        let s2a = article("Two feeds 1", feed: tech, hours: -5)
        let s2b = article("Two feeds 2", feed: news, hours: -5)
        let s3 = article("Foreign", feed: news, hours: -2, language: "en")
        let s4 = article("Single", feed: tech, hours: 0)
        let r1 = article("Read 1", feed: tech, read: true)
        let r2 = article("Read 2", feed: news, read: true)
        let c1 = article("Current 1", feed: tech)
        let c2 = article("Current 2", feed: tech)
        let sameFeed = Story(title: "1", articleIDs: [s1a.id, s1b.id])
        let twoFeeds = Story(title: "2", articleIDs: [s2a.id, s2b.id])
        let foreign = Story(title: "3", articleIDs: [s3.id])
        let single = Story(title: "4", articleIDs: [s4.id])
        let read = Story(title: "5", articleIDs: [r1.id, r2.id])
        let current = Story(
            title: "6", articleIDs: [c1.id, c2.id],
            summary: Summary(title: "T", text: "X", language: "cs", articleIDs: [c1.id, c2.id]))
        let excluded = Story(title: "7", articleIDs: [s1a.id, s4.id])
        let library = Library(
            feeds: [tech, news], articles: [s1a, s1b, s2a, s2b, s3, s4, r1, r2, c1, c2],
            stories: [sameFeed, twoFeeds, foreign, single, read, current, excluded])

        let pending = SummaryStep.pending(in: library, language: "cs", excluding: [excluded.id])

        #expect(pending == [twoFeeds.id, sameFeed.id, foreign.id])
    }

    @Test func buildsThePayloadOldestArticleFirst() throws {
        let first = article("First", feed: tech, hours: -3)
        var second = article("Second", feed: news, hours: -1)
        second.text = String(repeating: "word ", count: 400)
        let story = Story(title: "S", articleIDs: [second.id, first.id])
        let library = Library(feeds: [tech, news], articles: [first, second], stories: [story])

        let (input, map) = SummaryStep.payload(for: [story.id, UUID()], in: library, languageName: "Czech")

        #expect(input.outputLanguage == "Czech")
        #expect(input.stories.count == 1)
        #expect(input.stories[0].id == "s1")
        #expect(input.stories[0].articles.map(\.title) == ["First", "Second"])
        #expect(input.stories[0].articles.map(\.source) == ["Tech", "News"])
        #expect(input.stories[0].articles[1].text.count <= SummaryStep.excerptLength + 1)
        #expect(map["s1"]?.story == story.id)
        #expect(map["s1"]?.articles == [first.id, second.id])

        let request = SummaryStep.request(input, model: "m", effort: "low")
        #expect(request.systemPrompt == Prompts.summary)
        let json = try #require(JSONSerialization.jsonObject(with: request.input) as? [String: Any])
        #expect(Set(json.keys) == ["output_language", "stories"])
    }

    @Test func appliesSummariesOfKnownStoriesOnly() {
        let a = article("A", feed: tech)
        let b = article("B", feed: tech)
        let story = Story(title: "S", articleIDs: [a.id, b.id])
        let gone = UUID()
        var library = Library(feeds: [tech], articles: [a, b], stories: [story])
        let map: SummaryStep.IDMap = ["s1": (story.id, [a.id]), "s2": (gone, [])]
        let output = SummaryStep.Output(summaries: [
            .init(storyID: "s1", title: " Title ", summary: " - one\n- two "),
            .init(storyID: "s1", title: "Again", summary: "Dup"),
            .init(storyID: "s2", title: "Gone", summary: "Gone"),
            .init(storyID: "s9", title: "Unknown", summary: "Unknown"),
        ])

        let written = SummaryStep.apply(output, map: map, language: "cs", to: &library)

        #expect(written == [story.id])
        #expect(
            library.stories[story.id]?.summary
                == Summary(title: "Title", text: "- one\n- two", language: "cs", articleIDs: [a.id]))
    }

    @Test func ignoresEmptySummaries() {
        let a = article("A", feed: tech, language: "en")
        let story = Story(title: "S", articleIDs: [a.id])
        var library = Library(feeds: [tech], articles: [a], stories: [story])
        let written = SummaryStep.apply(
            SummaryStep.Output(summaries: [.init(storyID: "s1", title: "T", summary: "  ")]),
            map: ["s1": (story.id, [a.id])], language: "cs", to: &library)
        #expect(written.isEmpty)
        #expect(library.stories[story.id]?.summary == nil)
    }

    @Test func translatesTopicsInAnotherLanguage() throws {
        let english = Topic(name: "Games", description: "Video games.", language: "en")
        let unknown = Topic(name: "Apple", description: "Apple news.")
        let czech = Topic(name: "Věda", description: "Věda.", language: "cs")
        var library = Library(feeds: [], articles: [], topics: [english, unknown, czech])

        let pending = TopicTranslation.pending(in: library, language: "cs")
        #expect(Set(pending) == [english.id, unknown.id])

        let (payload, map) = TopicTranslation.payload(for: pending, in: library, languageName: "Czech")
        #expect(payload.outputLanguage == "Czech")
        #expect(payload.topics.count == 2)
        let gamesKey = try #require(map.first { $0.value == english.id }?.key)
        let request = TopicTranslation.request(payload, model: "m", effort: "low")
        #expect(request.systemPrompt == Prompts.translateTopics)

        TopicTranslation.apply(
            TopicTranslation.Payload(topics: [
                .init(id: gamesKey, name: "Hry", description: "Videohry."), .init(id: "t9", name: "X", description: ""),
            ]), map: map, language: "cs", to: &library)

        #expect(
            library.topics[english.id] == Topic(id: english.id, name: "Hry", description: "Videohry.", language: "cs"))
        // Left out of the answer: kept, but not asked about again.
        #expect(library.topics[unknown.id]?.name == "Apple")
        #expect(library.topics[unknown.id]?.language == "cs")
        #expect(TopicTranslation.pending(in: library, language: "cs").isEmpty)
    }
}
