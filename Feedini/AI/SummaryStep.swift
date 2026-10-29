import Foundation

/// The summary step: a title and a summary for stories where they add something (pure parts).
///
/// A story needs a summary when it has several articles, or an article in another language than the summary
/// language (then the summary is a translated gist). A single article in the summary language shows its own text.
enum SummaryStep {
    static let batchSize = 10
    static let excerptLength = 1000

    static func needsSummary(_ articles: [Article], language: String) -> Bool {
        articles.count > 1 || articles.contains { $0.language != nil && $0.language != language }
    }

    /// Written in the language and for exactly the story's articles.
    static func isCurrent(_ summary: Summary?, of story: Story, language: String) -> Bool {
        guard let summary else { return false }
        return summary.language == language && Set(summary.articleIDs) == Set(story.articleIDs)
    }

    /// Unread stories whose summary is missing or out of date, in the order they should be written: stories from
    /// several feeds first, then the others, newer before older. Read stories wait until they are unread again.
    static func pending(in library: Library, language: String, excluding: Set<Story.ID> = []) -> [Story.ID] {
        library.stories.values.compactMap { story -> (Story.ID, Bool, Date)? in
            guard !excluding.contains(story.id) else { return nil }
            let articles = story.articleIDs.compactMap { library.articles[$0] }
            guard articles.contains(where: { !$0.isRead }), needsSummary(articles, language: language),
                !isCurrent(story.summary, of: story, language: language)
            else { return nil }
            let feeds = Set(articles.map(\.feedID))
            return (story.id, feeds.count > 1, articles.map(\.date).max() ?? .distantPast)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            return lhs.0.uuidString < rhs.0.uuidString
        }
        .map(\.0)
    }

    struct Input: Encodable, Equatable {
        struct StoryItem: Encodable, Equatable {
            struct ArticleItem: Encodable, Equatable {
                var source: String
                var title: String
                var text: String
            }

            var id: String
            var articles: [ArticleItem]
        }

        var outputLanguage: String
        var stories: [StoryItem]

        private enum CodingKeys: String, CodingKey {
            case outputLanguage = "output_language", stories
        }
    }

    struct Output: Decodable, Equatable, Sendable {
        struct Item: Decodable, Equatable, Sendable {
            var storyID: String
            var title: String
            var summary: String

            private enum CodingKeys: String, CodingKey {
                case storyID = "story_id", title, summary
            }
        }

        var summaries: [Item]
    }

    /// What each short story ID stood for: the story and the articles sent with it.
    typealias IDMap = [String: (story: Story.ID, articles: [Article.ID])]

    static func payload(for storyIDs: [Story.ID], in library: Library, languageName: String) -> (Input, IDMap) {
        let sources = Dictionary(library.feeds.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        var map: IDMap = [:]
        var items: [Input.StoryItem] = []
        for story in storyIDs.compactMap({ library.stories[$0] }) {
            let articles = story.articleIDs.compactMap { library.articles[$0] }.sorted { $0.date < $1.date }
            guard !articles.isEmpty else { continue }
            let id = "s\(items.count + 1)"
            map[id] = (story.id, articles.map(\.id))
            items.append(
                Input.StoryItem(
                    id: id,
                    articles: articles.map {
                        Input.StoryItem.ArticleItem(
                            source: sources[$0.feedID] ?? "", title: $0.title,
                            text: HTMLText.excerpt($0.text, limit: excerptLength))
                    }))
        }
        return (Input(outputLanguage: languageName, stories: items), map)
    }

    static func request(_ input: Input, model: String, effort: String) -> ClaudeRequest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return ClaudeRequest(
            model: model, effort: effort, systemPrompt: Prompts.summary, schema: Prompts.summarySchema,
            input: (try? encoder.encode(input)) ?? Data())
    }

    /// Stores the summaries of stories that still exist; unknown IDs and empty answers are ignored. Returns the
    /// stories that got one.
    @discardableResult
    static func apply(_ output: Output, map: IDMap, language: String, to library: inout Library) -> Set<Story.ID> {
        var written = Set<Story.ID>()
        for item in output.summaries {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let (storyID, articles) = map[item.storyID], library.stories[storyID] != nil, !title.isEmpty,
                !text.isEmpty, !written.contains(storyID)
            else { continue }
            library.stories[storyID]?.summary = Summary(
                title: title, text: text, language: language, articleIDs: articles)
            written.insert(storyID)
        }
        return written
    }
}

/// Translates topic names and descriptions after the summary language changed: one cheap call for all topics in
/// another language.
enum TopicTranslation {
    struct Payload: Codable, Equatable {
        struct Item: Codable, Equatable {
            var id: String
            var name: String
            var description: String
        }

        var outputLanguage: String?
        var topics: [Item]

        private enum CodingKeys: String, CodingKey {
            case outputLanguage = "output_language", topics
        }
    }

    /// Topics whose language isn't the summary language (unknown counts as different).
    static func pending(in library: Library, language: String) -> [Topic.ID] {
        library.topics.values.filter { $0.language != language }.map(\.id).sorted { $0.uuidString < $1.uuidString }
    }

    static func payload(
        for topicIDs: [Topic.ID], in library: Library, languageName: String
    ) -> (
        Payload, [String: Topic.ID]
    ) {
        var map: [String: Topic.ID] = [:]
        var items: [Payload.Item] = []
        for topic in topicIDs.compactMap({ library.topics[$0] }) {
            let id = "t\(items.count + 1)"
            map[id] = topic.id
            items.append(Payload.Item(id: id, name: topic.name, description: topic.description))
        }
        return (Payload(outputLanguage: languageName, topics: items), map)
    }

    static func request(_ payload: Payload, model: String, effort: String) -> ClaudeRequest {
        ClaudeRequest(
            model: model, effort: effort, systemPrompt: Prompts.translateTopics, schema: Prompts.translateTopicsSchema,
            input: (try? JSONEncoder().encode(payload)) ?? Data())
    }

    /// Renames the topics; every topic sent counts as translated afterwards (also one the answer left out, so a
    /// stubborn topic can't cause a call on every refresh).
    static func apply(_ output: Payload, map: [String: Topic.ID], language: String, to library: inout Library) {
        for item in output.topics {
            guard let id = map[item.id] else { continue }
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                library.topics[id]?.name = name
                library.topics[id]?.description = item.description
            }
        }
        for id in map.values {
            library.topics[id]?.language = language
        }
    }
}
