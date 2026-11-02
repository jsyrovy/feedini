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
            shown = nil
            kept = []
            unsaved = [:]
        }
    }
    private(set) var cursor: ListRow?
    private(set) var expanded: Set<StoryEntry.ID> = []
    /// Entries read while shown; they stay in the list until the selection changes or a refresh.
    private(set) var kept: Set<StoryEntry.ID> = []
    /// Entries removed from Saved while it was shown, with their save dates: they stay in their place like kept ones.
    private(set) var unsaved: [StoryEntry.ID: Date] = [:]
    /// What the detail shows instead of the feed text.
    enum Shown: Equatable {
        /// The source page in the window (V).
        case page(Article.ID)
        /// The text of the source page (P).
        case preview(Article.ID)
    }

    private(set) var shown: Shown?
    /// The article whose source page the detail shows.
    var pageArticle: Article.ID? {
        if case .page(let id) = shown { id } else { nil }
    }
    /// The article whose page text the detail shows.
    var previewArticle: Article.ID? {
        if case .preview(let id) = shown { id } else { nil }
    }
    /// The keyboard shortcuts sheet (?).
    var isShowingShortcuts = false
    /// Increased when the story list should take the keyboard focus (after the page had it).
    private(set) var listFocusRequests = 0
    /// Reading and saving for ⌘Z / ⇧⌘Z; it lives as long as the app, not the window.
    private(set) var history = UndoHistory()
    /// Whether the main window is the key window, where ⌘Z takes back reading and saving (`UndoCommands`).
    var isMainWindowKey = false

    init(model: AppModel) {
        self.model = model
        model.onRefresh = { [weak self] in self?.dropReadEntries() }
        model.onLibraryChange = { [weak self] in
            self?.dropRemovedSelection()
            self?.followArticlesIntoStories()
        }
    }

    /// The entries of the list for the current selection.
    var entries: [StoryEntry] {
        guard selection != .saved else { return model.savedEntries(keeping: unsaved) }
        return StoryList.entries(model.entries, matching: selection, folders: model.folderIDsByFeed, keeping: kept)
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
        shown = nil
        guard let row, let entry = entry(row.entryID) else { return }
        if case .article = row {
            expanded.insert(entry.id)
        }
        let read = ReadRules.articlesRead(byVisiting: row, of: entry, isExpanded: expanded.contains(entry.id))
        if !read.isEmpty {
            kept.insert(entry.id)
            recording("Mark as Read", articles: read, row: row) { model.markRead(read) }
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
        case .previewPage(let id):
            togglePreview(id)
        case .summarizePage(let id):
            summarizePage(id)
        case .showShortcuts:
            isShowingShortcuts.toggle()
        case .toggleRead(let row):
            toggleRead(row)
        case .toggleSaved(let row):
            toggleSaved(row)
        case .saveWithSummary(let row, let article):
            saveWithSummary(row, article: article)
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
        case .markRead(let ids): recording("Mark as Read", articles: ids, row: row) { model.markRead(ids) }
        case .markUnread(let ids): recording("Mark as Unread", articles: ids, row: row) { model.markUnread(ids) }
        }
    }

    /// S: saves the row's item for later, or removes it from Saved (where it stays until the selection changes).
    func toggleSaved(_ row: ListRow) {
        guard let entry = entry(row.entryID), let item = entry.savedItem(at: row) else { return }
        if let savedAt = entry.savedAt(at: row) {
            if selection == .saved, case .story = row {
                unsaved[entry.id] = savedAt
            }
            recording("Remove from Saved", item, row: row) { model.setSaved(item, at: nil) }
        } else {
            recording("Save", item, row: row) { model.setSaved(item, at: .now) }
        }
    }

    /// Shift+S: saves the row's item unless it is saved and prepares the TL;DR of the article's source page in the
    /// background; the detail stays as it is.
    func saveWithSummary(_ row: ListRow, article: Article.ID?) {
        guard let entry = entry(row.entryID), let item = entry.savedItem(at: row) else { return }
        if entry.savedAt(at: row) == nil {
            recording("Save", item, row: row) { model.setSaved(item, at: .now) }
        }
        if let article {
            model.preparePage(article)
        }
    }

    /// Shift+A: everything in the current selection; the list empties. Saved isn't marked read: it is a list to
    /// come back to.
    func markAllRead() {
        guard selection != .saved else { return }
        let entries = entries
        let ids = entries.flatMap { $0.articles.filter { !$0.isRead }.map(\.id) }
        kept = []
        cursor = nil
        shown = nil
        recording("Mark All as Read", articles: ids, row: entries.first.map { .story($0.id) }) { model.markRead(ids) }
    }

    // MARK: Undo

    var undoName: String? { history.undoName }
    var redoName: String? { history.redoName }

    /// ⌘Z: takes back the last step of reading or saving that still has something to take back, and shows its row
    /// without reading it.
    func undo() {
        show(history.undo { model.restore($0) })
    }

    /// ⇧⌘Z: does the step taken back last again.
    func redo() {
        show(history.redo { model.restore($0) })
    }

    /// Changes reading or saving and records the change for ⌘Z. The callers only make changes that change something
    /// (they read unread articles, toggle, save what isn't saved).
    private func recording(
        _ name: String, articles: [Article.ID] = [], stories: [Story.ID] = [], row: ListRow?, _ change: () -> Void
    ) {
        let before = model.library.readingState(articles: articles, stories: stories)
        change()
        if !before.isEmpty {
            history.record(UndoHistory.Step(name: name, state: before, row: row))
        }
    }

    private func recording(_ name: String, _ item: SavedItem, row: ListRow, _ change: () -> Void) {
        switch item {
        case .article(let id): recording(name, articles: [id], row: row, change)
        case .story(let id): recording(name, stories: [id], row: row, change)
        }
    }

    /// Moves the cursor onto the row of an undone step – without visiting it, which would read it again. It stays in
    /// the list like an entry read there. A row that isn't in the current list (another selection) isn't shown.
    private func show(_ step: UndoHistory.Step?) {
        guard let row = step?.row else { return }
        kept.insert(row.entryID)
        if case .article = row {
            expanded.insert(row.entryID)
        }
        let rows = rows
        guard let target = rows.contains(row) ? row : rows.first(where: { $0 == .story(row.entryID) }) else { return }
        cursor = target
        shown = nil
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
        shown = cursorArticle.map { .page($0.id) }
        if let pageArticle {
            model.pageOpened(pageArticle)
        }
    }

    func closePage() {
        shown = nil
        listFocusRequests += 1
    }

    /// P: the page text instead of the feed text (loaded unless stored), or the feed text again. From the source page
    /// it goes straight to the text.
    func togglePreview(_ id: Article.ID) {
        guard previewArticle != id else {
            shown = nil
            return
        }
        shown = .preview(id)
        model.loadPage(id)
    }

    /// T: from the source page in the window it goes back to the text, where the summary shows.
    func summarizePage(_ id: Article.ID) {
        if pageArticle != nil {
            closePage()
        }
        model.summarizePage(id)
    }

    /// The article under the cursor: the article row, or the only article of a story.
    var cursorArticle: Article? {
        guard let cursor else { return nil }
        return entry(cursor.entryID)?.singleArticle(at: cursor)
    }

    // MARK: Refresh

    private func dropReadEntries() {
        kept = cursor.map { [$0.entryID] } ?? []
        unsaved = unsaved.filter { $0.key == cursor?.entryID }
    }

    /// A removed feed, folder or topic can't stay selected; All is selected instead.
    private func dropRemovedSelection() {
        if !model.library.contains(selection) {
            selection = .all
        }
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
