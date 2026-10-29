/// A row of the story list: a story, or an article inside an expanded story.
enum ListRow: Hashable, Sendable {
    case story(StoryEntry.ID)
    case article(StoryEntry.ID, Article.ID)

    var entryID: StoryEntry.ID {
        switch self {
        case .story(let id), .article(let id, _): id
        }
    }
}

/// What reading does to the read state (pure).
enum ReadRules {
    enum Change: Equatable, Sendable {
        case markRead([Article.ID])
        case markUnread([Article.ID])
    }

    /// Moving onto a row reads it. A collapsed story is read as a whole (its summary covered all its articles); the
    /// heading of an expanded story reads nothing, its articles are read one by one.
    static func articlesRead(byVisiting row: ListRow, of entry: StoryEntry, isExpanded: Bool) -> [Article.ID] {
        switch row {
        case .story:
            guard !isExpanded else { return [] }
            return entry.articles.filter { !$0.isRead }.map(\.id)
        case .article(_, let id):
            return entry.article(id)?.isRead == false ? [id] : []
        }
    }

    /// M: an article toggles itself; a story becomes unread with all its articles when it is read, otherwise read.
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
