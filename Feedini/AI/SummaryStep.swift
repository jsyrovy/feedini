import Foundation

/// Which stories with a single article get an AI title and summary (Settings → AI).
enum SingleArticleSummaries: String, CaseIterable, Sendable {
    /// None: a single article shows its own title and text.
    case never
    /// Articles in another language than the summary language (the summary is a translated gist).
    case otherLanguages
    /// Every article.
    case always
}

/// The summary step: a title and a summary for stories where they add something (pure parts).
///
/// A story needs a summary when it has several articles; a story with a single article only as `singleArticles`
/// says. Without one, a single article shows its own text.
enum SummaryStep {
    static let batchSize = 10
    static let excerptLength = 1000

    /// An unknown article language counts as the summary language.
    static func needsSummary(
        _ articles: [Article], language: String, singleArticles: SingleArticleSummaries
    ) -> Bool {
        guard let article = articles.first else { return false }
        if articles.count > 1 { return true }
        switch singleArticles {
        case .never: return false
        case .otherLanguages: return article.language != nil && article.language != language
        case .always: return true
        }
    }

    /// Written in the language and for exactly the story's articles.
    static func isCurrent(_ summary: Summary?, of story: Story, language: String) -> Bool {
        guard let summary, summary.language == language, summary.articleIDs.count == story.articleIDs.count else {
            return false
        }
        return Set(summary.articleIDs) == Set(story.articleIDs)
    }

    /// Unread or saved stories (saved as a whole or with a saved article) whose summary is missing or out of date, in
    /// the order they should be written: stories from several feeds first, then the others, newer before older. Other
    /// read stories wait until they are unread again.
    static func pending(
        in library: Library, language: String, singleArticles: SingleArticleSummaries,
        excluding: Set<Story.ID> = []
    ) -> [Story.ID] {
        library.stories.values.compactMap { story -> (Story.ID, Bool, Date)? in
            guard !excluding.contains(story.id) else { return nil }
            let articles = library.articles(of: story)
            guard articles.contains(where: { !$0.isRead }) || story.isKeptBySaving(articles),
                needsSummary(articles, language: language, singleArticles: singleArticles),
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
        let sources = library.sourceTitles()
        var map: IDMap = [:]
        var items: [Input.StoryItem] = []
        for story in storyIDs.compactMap({ library.stories[$0] }) {
            let articles = library.articles(of: story).sorted { $0.date < $1.date }
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
