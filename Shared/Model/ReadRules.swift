/// A row of the story list: a story, or an article inside an expanded story.
enum ListRow: Hashable, Sendable {
    case story(StoryEntry.ID)
    case article(StoryEntry.ID, Article.ID)

    var entryID: StoryEntry.ID {
        switch self {
        case .story(let id), .article(let id, _): id
        }
    }

    /// The row `offset` places away where this row is shown (next / previous in an iOS detail): a story's row among
    /// the entries of the list, an article among the articles of its story. `nil` past either end, or when the row
    /// isn't in `entries` anymore.
    func neighbor(_ offset: Int, in entries: [StoryEntry]) -> ListRow? {
        switch self {
        case .story(let id):
            entries.element(offset, from: id).map { .story($0.id) }
        case .article(let entryID, let articleID):
            entries.first { $0.id == entryID }?.articles.element(offset, from: articleID).map {
                .article(entryID, $0.id)
            }
        }
    }
}

extension Array where Element: Identifiable {
    /// The element `offset` places away from the one with `id`; `nil` past either end or without that element.
    fileprivate func element(_ offset: Int, from id: Element.ID) -> Element? {
        guard let index = firstIndex(where: { $0.id == id }), indices.contains(index + offset) else { return nil }
        return self[index + offset]
    }
}

/// What reading does to the read state (pure).
enum ReadRules {
    enum Change: Equatable, Sendable {
        case markRead([Article.ID])
        case markUnread([Article.ID])
    }

    /// Moving onto a row reads it. A collapsed story is read as a whole (its summary covered all the articles it
    /// shows); the heading of an expanded story reads nothing, its articles are read one by one.
    static func articlesRead(byVisiting row: ListRow, of entry: StoryEntry, isExpanded: Bool) -> [Article.ID] {
        switch row {
        case .story:
            guard !isExpanded else { return [] }
            return entry.articles.filter { !$0.isRead }.map(\.id)
        case .article(_, let id):
            return entry.article(id)?.isRead == false ? [id] : []
        }
    }

    /// M: an article toggles itself; a story becomes unread with all the articles it shows when they are read,
    /// otherwise read.
    static func toggle(_ row: ListRow, of entry: StoryEntry) -> Change {
        switch row {
        case .story:
            let ids = entry.articles.map(\.id)
            return entry.isRead ? .markUnread(ids) : .markRead(ids)
        case .article(_, let id):
            return entry.article(id)?.isRead == true ? .markUnread([id]) : .markRead([id])
        }
    }
}

extension ListRow {
    /// The rows of the list: every entry, followed by its articles when expanded.
    static func rows(_ entries: [StoryEntry], expanded: Set<StoryEntry.ID>) -> [ListRow] {
        entries.flatMap { entry -> [ListRow] in
            guard entry.isMultiArticle, expanded.contains(entry.id) else { return [.story(entry.id)] }
            return [.story(entry.id)] + entry.articles.map { .article(entry.id, $0.id) }
        }
    }
}
