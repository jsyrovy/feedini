import AppKit
import Observation

/// The state of the main window: sidebar selection, the cursor in the story list, expanded stories and the source
/// page shown in the detail. Carries out the keyboard decisions of `KeyboardNavigation` and the read rules.
@MainActor
@Observable
final class Reader {
    let model: AppModel

    /// The sidebar selection; changing it drops read entries from the list.
    var selection: SidebarSelection = .all {
        didSet {
            guard selection != oldValue else { return }
            cursor = nil
            pageArticle = nil
            kept = []
        }
    }
    private(set) var cursor: ListRow?
    private(set) var expanded: Set<StoryEntry.ID> = []
    /// Entries read while shown; they stay in the list until the selection changes or a refresh.
    private(set) var kept: Set<StoryEntry.ID> = []
    /// The article whose source page the detail shows instead of the feed text.
    private(set) var pageArticle: Article.ID?
    /// Increased when the story list should take the keyboard focus (after the page had it).
    private(set) var listFocusRequests = 0

    init(model: AppModel) {
        self.model = model
        model.onRefresh = { [weak self] in self?.dropReadEntries() }
        model.onLibraryChange = { [weak self] in self?.followArticlesIntoStories() }
    }

    /// The entries of the list for the current selection.
    var entries: [StoryEntry] {
        StoryList.entries(model.entries, matching: selection, keeping: kept)
    }

    var rows: [ListRow] {
        KeyboardNavigation.rows(entries, expanded: expanded)
    }

    func entry(_ id: StoryEntry.ID) -> StoryEntry? {
        model.entry(id)
    }

    var opensInWindow: Bool {
        model.preferences.pageOpening == .window
    }

    // MARK: Moving

    /// Moves the cursor onto a row, which reads it (`ReadRules`).
    func visit(_ row: ListRow?) {
        guard row != cursor else { return }
        cursor = row
        pageArticle = nil
        guard let row, let entry = entry(row.entryID) else { return }
        if case .article = row {
            expanded.insert(entry.id)
        }
        let read = ReadRules.articlesRead(byVisiting: row, of: entry, isExpanded: expanded.contains(entry.id))
        if !read.isEmpty {
            kept.insert(entry.id)
            model.markRead(read)
        }
    }

    /// Handles a key of the story list; returns whether it did anything.
    @discardableResult
    func handle(_ key: ListKey) -> Bool {
        let action = KeyboardNavigation.action(
            for: key, at: cursor, entry: cursor.flatMap { entry($0.entryID) }, rows: rows, expanded: expanded,
            opensInWindow: opensInWindow, pageArticle: pageArticle)
        switch action {
        case .none:
            return false
        case .select(let row):
            visit(row)
        case .expand(let id):
            expanded.insert(id)
        case .collapse(let id):
            expanded.remove(id)
            visit(.story(id))
        case .openPage(let url, let inWindow):
            open(url, inWindow: inWindow)
        case .closePage:
            closePage()
        case .toggleRead(let row):
            toggleRead(row)
        case .refresh:
            model.refreshNow()
        case .markAllRead:
            markAllRead()
        }
        return true
    }

    func toggleRead(_ row: ListRow) {
        guard let entry = entry(row.entryID) else { return }
        kept.insert(entry.id)
        switch ReadRules.toggle(row, of: entry) {
        case .markRead(let ids): model.markRead(ids)
        case .markUnread(let ids): model.markUnread(ids)
        }
    }

    /// Shift+A: everything in the current selection; the list empties.
    func markAllRead() {
        let ids = entries.flatMap { $0.articles.filter { !$0.isRead }.map(\.id) }
        kept = []
        cursor = nil
        pageArticle = nil
        model.markRead(ids)
    }

    func toggleExpanded(_ id: StoryEntry.ID) {
        if expanded.contains(id) {
            expanded.remove(id)
            if cursor?.entryID == id {
                visit(.story(id))
            }
        } else {
            expanded.insert(id)
        }
    }

    // MARK: Source pages

    /// Opens the article's source page in the window or in the default browser.
    func open(_ url: URL, inWindow: Bool) {
        guard inWindow else {
            NSWorkspace.shared.open(url)
            return
        }
        pageArticle = cursorArticle?.id
    }

    func closePage() {
        pageArticle = nil
        listFocusRequests += 1
    }

    /// The article under the cursor: the article row, or the only article of a story.
    var cursorArticle: Article? {
        guard let cursor, let entry = entry(cursor.entryID) else { return nil }
        if case .story = cursor, entry.isMultiArticle {
            return nil
        }
        return entry.article(at: cursor)
    }

    // MARK: Refresh

    private func dropReadEntries() {
        kept = cursor.map { [$0.entryID] } ?? []
    }

    /// When the AI puts a loose article into a story, the list entry changes its ID. The cursor follows the article
    /// (into the expanded story if it has several articles), and kept entries stay kept, without reading anything.
    private func followArticlesIntoStories() {
        let isLoose: (StoryEntry.ID) -> Bool = { if case .loose = $0 { true } else { false } }
        guard cursor.map({ isLoose($0.entryID) }) == true || kept.contains(where: isLoose) else { return }
        let index = model.library.storyIDsByArticle()
        kept = Set(
            kept.map { id in
                if case .loose(let article) = id, let story = index[article] { .story(story) } else { id }
            })
        guard let cursor, case .loose(let article) = cursor.entryID, let storyID = index[article],
            let story = model.library.stories[storyID]
        else { return }
        if story.articleIDs.count > 1 {
            expanded.insert(.story(storyID))
            self.cursor = .article(.story(storyID), article)
        } else {
            self.cursor = .story(.story(storyID))
        }
    }
}
