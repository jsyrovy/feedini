import Foundation

/// Everything Feedini keeps: feeds, articles, stories, topics and tombstones. A value type; the app holds one on the
/// main actor and hands copies to the store for saving.
struct Library: Sendable, Equatable {
    /// In the order they were added.
    var feeds: [Feed] = []
    var articles: [Article.ID: Article] = [:]
    var stories: [Story.ID: Story] = [:]
    var topics: [Topic.ID: Topic] = [:]
    var tombstones: [Tombstone.Key: Tombstone] = [:]
    /// AI calls per day, oldest first (`recordAICall`).
    var usage: [AIUsageDay] = []

    func feed(_ id: Feed.ID) -> Feed? {
        feeds.first { $0.id == id }
    }

    /// The articles of a story that exist, in the story's order.
    func articles(of story: Story) -> [Article] {
        story.articleIDs.compactMap { articles[$0] }
    }

    /// The story of every article that belongs to one.
    func storyIDsByArticle() -> [Article.ID: Story.ID] {
        var index: [Article.ID: Story.ID] = [:]
        for story in stories.values {
            for articleID in story.articleIDs {
                index[articleID] = story.id
            }
        }
        return index
    }

    // MARK: Read state

    /// Marks the articles read. A story whose articles are all read loses its "new" marks.
    mutating func markRead(_ ids: some Sequence<Article.ID>, at date: Date) {
        var changed = false
        for id in ids where articles[id]?.readAt == nil {
            articles[id]?.readAt = date
            changed = true
        }
        if changed {
            clearNewMarksOfReadStories()
        }
    }

    mutating func markUnread(_ ids: some Sequence<Article.ID>) {
        for id in ids {
            articles[id]?.readAt = nil
        }
    }

    private mutating func clearNewMarksOfReadStories() {
        for (id, story) in stories where !story.newArticleIDs.isEmpty {
            if story.articleIDs.allSatisfy({ articles[$0]?.isRead ?? true }) {
                stories[id]?.newArticleIDs = []
            }
        }
    }

    // MARK: Feeds

    /// Removes the feed with its articles and tombstones. Stories lose its articles; stories left empty are removed.
    mutating func removeFeed(_ id: Feed.ID) {
        feeds.removeAll { $0.id == id }
        let removed = Set(articles.values.filter { $0.feedID == id }.map(\.id))
        for articleID in removed {
            articles[articleID] = nil
        }
        removeFromStories(removed)
        tombstones = tombstones.filter { $0.key.feedID != id }
    }

    /// Takes the articles out of their stories and removes stories left empty.
    mutating func removeFromStories(_ articleIDs: Set<Article.ID>) {
        guard !articleIDs.isEmpty else { return }
        for (id, story) in stories where story.articleIDs.contains(where: articleIDs.contains) {
            let remaining = story.articleIDs.filter { !articleIDs.contains($0) }
            if remaining.isEmpty {
                stories[id] = nil
            } else {
                stories[id]?.articleIDs = remaining
                stories[id]?.newArticleIDs.subtract(articleIDs)
            }
        }
    }
}

extension Tombstone {
    struct Key: Hashable, Sendable {
        var feedID: Feed.ID
        var key: String
    }

    var id: Key { Key(feedID: feedID, key: key) }
}

extension Article {
    var tombstoneKey: Tombstone.Key { Tombstone.Key(feedID: feedID, key: key) }
}

// Saved as arrays (dictionaries with non-string keys would be encoded as flat key/value arrays), in a stable order so
// that unchanged data gives an unchanged file.
extension Library: Codable {
    private enum CodingKeys: String, CodingKey {
        case feeds, articles, stories, topics, tombstones, usage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        feeds = try container.decode([Feed].self, forKey: .feeds)
        articles = Self.index(try container.decode([Article].self, forKey: .articles), by: \.id)
        stories = Self.index(try container.decode([Story].self, forKey: .stories), by: \.id)
        topics = Self.index(try container.decode([Topic].self, forKey: .topics), by: \.id)
        tombstones = Self.index(try container.decode([Tombstone].self, forKey: .tombstones), by: \.id)
        // Added after the first version; older files have none.
        usage = try container.decodeIfPresent([AIUsageDay].self, forKey: .usage) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(feeds, forKey: .feeds)
        try container.encode(
            articles.values.map { (date: $0.firstSeen, id: $0.id.uuidString, article: $0) }
                .sorted { ($0.date, $0.id) < ($1.date, $1.id) }.map(\.article),
            forKey: .articles)
        try container.encode(Self.sorted(stories.values) { $0.id.uuidString }, forKey: .stories)
        try container.encode(Self.sorted(topics.values) { $0.id.uuidString }, forKey: .topics)
        // Feed IDs have a fixed length, so "feed key" sorts like (feed, key).
        try container.encode(
            Self.sorted(tombstones.values) { "\($0.feedID.uuidString) \($0.key)" }, forKey: .tombstones)
        try container.encode(usage, forKey: .usage)
    }

    /// Sorted by a key computed once per value (not twice per comparison).
    private static func sorted<Value>(_ values: some Collection<Value>, by key: (Value) -> String) -> [Value] {
        values.map { (key: key($0), value: $0) }.sorted { $0.key < $1.key }.map(\.value)
    }

    /// Later duplicates win; there are none unless the file was edited by hand.
    private static func index<Value, Key: Hashable>(_ values: [Value], by key: KeyPath<Value, Key>) -> [Key: Value] {
        Dictionary(values.map { ($0[keyPath: key], $0) }, uniquingKeysWith: { _, last in last })
    }
}
