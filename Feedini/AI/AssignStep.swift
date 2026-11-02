import Foundation

/// The assign step: new articles join existing stories or form new ones, with topics. This file builds the payload
/// (pure); `AssignValidation` applies the answer.
enum AssignStep {
    static let excerptLength = 600

    struct Input: Encodable, Equatable {
        struct TopicItem: Encodable, Equatable {
            var id: String
            var name: String
            var description: String
        }

        struct StoryItem: Encodable, Equatable {
            struct ArticleItem: Encodable, Equatable {
                var source: String
                var title: String
            }

            var id: String
            var title: String
            var topicID: String?
            var articles: [ArticleItem]

            private enum CodingKeys: String, CodingKey {
                case id, title, topicID = "topic_id", articles
            }
        }

        struct ArticleItem: Encodable, Equatable {
            var id: String
            var source: String
            var title: String
            var published: String?
            var description: String
        }

        var outputLanguage: String
        var topics: [TopicItem]
        var stories: [StoryItem]
        var newArticles: [ArticleItem]

        private enum CodingKeys: String, CodingKey {
            case outputLanguage = "output_language", topics, stories, newArticles = "new_articles"
        }
    }

    struct Output: Decodable, Equatable, Sendable {
        struct Attachment: Decodable, Equatable, Sendable {
            var storyID: String
            var articleIDs: [String]

            private enum CodingKeys: String, CodingKey {
                case storyID = "story_id", articleIDs = "article_ids"
            }
        }

        struct NewTopic: Decodable, Equatable, Sendable {
            var key: String
            var name: String
            var description: String
        }

        struct NewStory: Decodable, Equatable, Sendable {
            var title: String
            var topic: String
            var articleIDs: [String]

            private enum CodingKeys: String, CodingKey {
                case title, topic, articleIDs = "article_ids"
            }
        }

        var attach: [Attachment]
        var newTopics: [NewTopic]
        var newStories: [NewStory]

        private enum CodingKeys: String, CodingKey {
            case attach, newTopics = "new_topics", newStories = "new_stories"
        }
    }

    /// The short IDs of one call (`a1`, `s1`, `t1`) and what they stand for.
    struct IDMap: Equatable, Sendable {
        var articles: [String: Article.ID] = [:]
        var stories: [String: Story.ID] = [:]
        var topics: [String: Topic.ID] = [:]
    }

    /// The payload for the new articles: candidate stories are those whose newest article is younger than the attach
    /// window (read ones too, so a new article can join a known story); topics are those of unread stories.
    static func payload(
        for newArticles: [Article.ID], in library: Library, language: String, now: Date
    ) -> (Input, IDMap) {
        var map = IDMap()
        let cutoff = now.addingTimeInterval(-Retention.attachWindow)
        let sources = library.sourceTitles()

        let candidates = library.stories.values
            .map { story in (story, library.articles(of: story)) }
            .filter { _, articles in articles.contains { $0.date >= cutoff } }
            .sorted { lhs, rhs in newest(lhs.1) > newest(rhs.1) }
        let unreadTopics = Set(
            library.stories.values
                .filter { story in story.articleIDs.contains { library.articles[$0]?.isRead == false } }
                .compactMap(\.topicID))
        let topics = library.topics.values.filter { unreadTopics.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var topicItems: [Input.TopicItem] = []
        var shortTopic: [Topic.ID: String] = [:]
        for topic in topics {
            let id = "t\(topicItems.count + 1)"
            map.topics[id] = topic.id
            shortTopic[topic.id] = id
            topicItems.append(Input.TopicItem(id: id, name: topic.name, description: topic.description))
        }

        var storyItems: [Input.StoryItem] = []
        for (story, articles) in candidates {
            let id = "s\(storyItems.count + 1)"
            map.stories[id] = story.id
            storyItems.append(
                Input.StoryItem(
                    id: id, title: articles.count == 1 ? articles[0].title : story.title,
                    topicID: story.topicID.flatMap { shortTopic[$0] },
                    articles: articles.map {
                        Input.StoryItem.ArticleItem(source: sources[$0.feedID] ?? "", title: $0.title)
                    }))
        }

        var articleItems: [Input.ArticleItem] = []
        for article in newArticles.compactMap({ library.articles[$0] }) {
            let id = "a\(articleItems.count + 1)"
            map.articles[id] = article.id
            articleItems.append(
                Input.ArticleItem(
                    id: id, source: sources[article.feedID] ?? "", title: article.title,
                    published: article.published?.formatted(.iso8601),
                    description: HTMLText.excerpt(article.text, limit: excerptLength)))
        }

        return (
            Input(outputLanguage: language, topics: topicItems, stories: storyItems, newArticles: articleItems), map
        )
    }

    private static func newest(_ articles: [Article]) -> Date {
        articles.map(\.date).max() ?? .distantPast
    }
}
