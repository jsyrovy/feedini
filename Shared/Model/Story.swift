import Foundation

/// Articles about one real-world event, grouped by the AI. Articles the AI hasn't processed yet belong to no story and
/// are shown on their own.
struct Story: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var topicID: Topic.ID?
    /// In the order they joined the story.
    var articleIDs: [Article.ID]
    /// The AI summary, if the story needs one and it has been written.
    var summary: Summary?

    init(
        id: UUID = UUID(), title: String, topicID: Topic.ID? = nil, articleIDs: [Article.ID], summary: Summary? = nil
    ) {
        self.id = id
        self.title = title
        self.topicID = topicID
        self.articleIDs = articleIDs
        self.summary = summary
    }
}

/// What the AI wrote about a story: a title and what its unread articles said together when it was written (or, for
/// one article in another language, a translated gist).
struct Summary: Codable, Sendable, Hashable {
    var title: String
    /// Sentences, or lines starting with "- " for bigger stories.
    var text: String
    /// The language code it was written in.
    var language: String
    /// The articles it covered; a story with an unread article it didn't cover needs a new one.
    var articleIDs: [Article.ID]
}

/// A group of stories in the sidebar, created by the AI.
struct Topic: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    /// One sentence about what belongs in the topic, for the AI.
    var description: String
    /// The language code of the name and description; `nil` when unknown.
    var language: String?

    init(id: UUID = UUID(), name: String, description: String, language: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.language = language
    }
}
