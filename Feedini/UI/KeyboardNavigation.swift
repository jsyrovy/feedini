import Foundation

/// The keys of the story list (see "Reading model" in CLAUDE.md).
enum ListKey: CaseIterable, Sendable {
    /// J / ↓
    case next
    /// K / ↑
    case previous
    /// L / →
    case expand
    /// H / ←
    case collapse
    /// Esc
    case escape
    /// V / Enter
    case open
    /// Shift+V / Shift+Enter
    case openOther
    /// P: the text of the source page instead of the feed text
    case preview
    /// T: a TL;DR of the source page
    case summarizePage
    /// M
    case toggleRead
    /// S: save for later, or remove from Saved
    case save
    /// Shift+S: save for later with a TL;DR of the source page
    case saveWithSummary
    /// R
    case refresh
    /// Shift+A
    case markAllRead
    /// ?
    case shortcuts
}

/// What a key does in the story list (pure): the decision only, carried out by the reader.
enum KeyboardNavigation {
    enum Action: Equatable, Sendable {
        case select(ListRow)
        case expand(StoryEntry.ID)
        /// Collapses the story and moves onto its row.
        case collapse(StoryEntry.ID)
        case openPage(URL, inWindow: Bool)
        /// Back from the source page to the feed text.
        case closePage
        /// Shows the text of the source page instead of the feed text, or the feed text again.
        case previewPage(Article.ID)
        case summarizePage(Article.ID)
        case toggleRead(ListRow)
        case toggleSaved(ListRow)
        /// Saves the row's item (never removes it) and summarizes the article's source page, if it has one.
        case saveWithSummary(ListRow, Article.ID?)
        case refresh
        case markAllRead
        case showShortcuts
        case none
    }

    /// The rows of the list: every entry, followed by its articles when expanded.
    static func rows(_ entries: [StoryEntry], expanded: Set<StoryEntry.ID>) -> [ListRow] {
        entries.flatMap { entry -> [ListRow] in
            guard entry.isMultiArticle, expanded.contains(entry.id) else { return [.story(entry.id)] }
            return [.story(entry.id)] + entry.articles.map { .article(entry.id, $0.id) }
        }
    }

    /// - Parameters:
    ///   - entry: the entry of the cursor's row.
    ///   - opensInWindow: the default way of opening source pages (Settings → General).
    ///   - pageArticle: the article whose source page the detail shows, if any.
    static func action(
        for key: ListKey, at cursor: ListRow?, entry: StoryEntry?, rows: [ListRow], expanded: Set<StoryEntry.ID>,
        opensInWindow: Bool, pageArticle: Article.ID?
    ) -> Action {
        switch key {
        case .refresh: return .refresh
        case .markAllRead: return .markAllRead
        case .shortcuts: return .showShortcuts
        case .next, .previous: return move(key == .next ? 1 : -1, from: cursor, in: rows)
        default: break
        }
        guard let cursor, let entry, entry.id == cursor.entryID else { return .none }
        let isExpanded = entry.isMultiArticle && expanded.contains(entry.id)

        switch (key, cursor) {
        case (.toggleRead, _):
            return .toggleRead(cursor)
        case (.save, _):
            return .toggleSaved(cursor)
        case (.saveWithSummary, _):
            return .saveWithSummary(cursor, entry.singleArticle(at: cursor).flatMap { $0.link != nil ? $0.id : nil })
        case (.expand, .story):
            guard entry.isMultiArticle else { return .none }
            return isExpanded ? .select(.article(entry.id, entry.articles[0].id)) : .expand(entry.id)
        case (.escape, _) where pageArticle != nil:
            return .closePage
        case (.collapse, .article), (.escape, .article):
            return .collapse(entry.id)
        case (.collapse, .story), (.escape, .story):
            return isExpanded ? .collapse(entry.id) : .none
        case (.open, .story) where entry.isMultiArticle:
            return isExpanded ? .none : .expand(entry.id)
        case (.openOther, .story) where entry.isMultiArticle:
            return .none
        case (.preview, _), (.summarizePage, _):
            guard let article = entry.singleArticle(at: cursor), article.link != nil else { return .none }
            return key == .preview ? .previewPage(article.id) : .summarizePage(article.id)
        case (.open, _), (.openOther, _):
            guard let article = entry.article(at: cursor) else { return .none }
            let inWindow = (key == .open) == opensInWindow
            if inWindow && pageArticle == article.id {
                return .closePage
            }
            guard let link = article.link else { return .none }
            return .openPage(link, inWindow: inWindow)
        default:
            return .none
        }
    }

    private static func move(_ step: Int, from cursor: ListRow?, in rows: [ListRow]) -> Action {
        guard let cursor, let index = rows.firstIndex(of: cursor) else {
            return rows.first.map(Action.select) ?? .none
        }
        let target = index + step
        guard rows.indices.contains(target) else { return .none }
        return .select(rows[target])
    }
}
