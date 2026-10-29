import Foundation

/// Articles about one real-world event, grouped by the AI. Articles the AI hasn't processed yet belong to no story and
/// are shown on their own.
struct Story: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var topicID: Topic.ID?
    /// In the order they joined the story.
    var articleIDs: [Article.ID]
    /// Articles that joined after the story had been read ("+1 new"); cleared once the story is read again.
    var newArticleIDs: Set<Article.ID>

    init(
        id: UUID = UUID(), title: String, topicID: Topic.ID? = nil, articleIDs: [Article.ID],
        newArticleIDs: Set<Article.ID> = []
    ) {
        self.id = id
        self.title = title
        self.topicID = topicID
        self.articleIDs = articleIDs
        self.newArticleIDs = newArticleIDs
    }
}

/// A group of stories in the sidebar, created by the AI.
struct Topic: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    /// One sentence about what belongs in the topic, for the AI.
    var description: String

    init(id: UUID = UUID(), name: String, description: String) {
        self.id = id
        self.name = name
        self.description = description
    }
}
