import AppKit
import Observation

/// The state of the main window: sidebar selection, the cursor in the story list, expanded stories, the articles
/// read while the list is shown and the source page shown in the detail. Carries out the keyboard decisions of
/// `KeyboardNavigation` and the read rules.
@MainActor
@Observable
final class Reader {
    let model: AppModel

    /// The sidebar selection; changing it drops read entries from the list.
    var selection: SidebarSelection = .all {
        didSet {
            guard selection != oldValue else { return }
            resetList()
        }
    }
    private(set) var cursor: ListRow?
    private(set) var expanded: Set<StoryEntry.ID> = []
    /// Articles read while the list is shown; they stay in it (and in their stories) until the selection changes or a
    /// refresh.
    private(set) var keptArticles: Set<Article.ID> = []
    /// Articles removed from Saved while it was shown, with their save dates: they stay in their place like kept
    /// entries.
    private(set) var unsaved: [Article.ID: Date] = [:]
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
    /// The sheet for restoring a backup (File → Restore from Backup…).
    var isShowingRestore = false
    /// The sheet for saving a link (+, File → Save Link…).
    var isShowingSaveLink = false
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
        model.onRestore = { [weak self] in self?.startOver() }
    }

    /// The entries of the list for the current selection, in the chosen order.
    var entries: [StoryEntry] {
        let entries =
            selection == .saved
            ? model.savedEntries(keeping: unsaved)
            : StoryList.entries(
                model.entries, matching: selection, folders: model.folderIDsByFeed, keeping: keptArticles)
        return StoryList.ordered(entries, model.preferences.listOrder)
    }

    var rows: [ListRow] {
        KeyboardNavigation.rows(entries, expanded: expanded)
    }

    /// The entry with the articles it shows (`StoryEntry.visible(keeping:)`); `nil` when it shows none. Saved shows
    /// its articles read or not.
    func entry(_ id: StoryEntry.ID) -> StoryEntry? {
        guard let entry = model.entry(id) else { return nil }
        if case .savedArticle = id {
            return entry
        }
        return entry.visible(keeping: keptArticles)
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
            keptArticles.formUnion(read)
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
        case .reloadPage(let id):
            reloadPage(id)
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
        switch ReadRules.toggle(row, of: entry) {
        case .markRead(let ids):
            keptArticles.formUnion(ids)
            recording("Mark as Read", articles: ids, row: row) { model.markRead(ids) }
        case .markUnread(let ids): recording("Mark as Unread", articles: ids, row: row) { model.markUnread(ids) }
        }
    }

    /// S: saves the row's article for later, or removes it from Saved (where it stays until the selection changes).
    /// The row of a story with several articles has none.
    func toggleSaved(_ row: ListRow) {
        guard let article = entry(row.entryID)?.singleArticle(at: row) else { return }
        let id = article.id
        if let savedAt = article.savedAt {
            if selection == .saved {
                unsaved[id] = savedAt
            }
            recording("Remove from Saved", articles: [id], row: row) { model.setSaved(id, at: nil) }
        } else {
            recording("Save", articles: [id], row: row) { model.setSaved(id, at: .now) }
        }
    }

    /// Shift+S: saves the row's article unless it is saved and prepares the TL;DR of its source page (when it has a
    /// link) in the background; the detail stays as it is.
    func saveWithSummary(_ row: ListRow, article page: Article.ID?) {
        guard let article = entry(row.entryID)?.singleArticle(at: row) else { return }
        let id = article.id
        if !article.isSaved {
            recording("Save", articles: [id], row: row) { model.setSaved(id, at: .now) }
        }
        if let page {
            model.preparePage(page)
        }
    }

    /// Shift+A: everything in the current selection; the list empties. Saved isn't marked read: it is a list to
    /// come back to.
    func markAllRead() {
        guard selection != .saved else { return }
        let entries = entries
        let ids = entries.flatMap { $0.articles.filter { !$0.isRead }.map(\.id) }
        keptArticles = []
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
    private func recording(_ name: String, articles: [Article.ID], row: ListRow?, _ change: () -> Void) {
        let before = model.library.readingState(articles: articles)
        change()
        if !before.isEmpty {
            history.record(UndoHistory.Step(name: name, state: before, row: row))
        }
    }

    /// Moves the cursor onto the row of an undone step – without visiting it, which would read it again. Its articles
    /// stay in the list like articles read there. A row that isn't in the current list (another selection) isn't shown.
    private func show(_ step: UndoHistory.Step?) {
        guard let step, let row = step.row else { return }
        keptArticles.formUnion(step.state.articles.keys)
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

    /// P on a saved link: loads its page again. From the source page in the window (where the user may have logged in)
    /// it goes back to the text.
    func reloadPage(_ id: Article.ID) {
        if pageArticle != nil {
            closePage()
        }
        model.reloadPage(id)
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

    /// The list of a new selection: no cursor, nothing shown or kept.
    private func resetList() {
        cursor = nil
        shown = nil
        keptArticles = []
        unsaved = [:]
    }

    /// After a restore: nothing of the replaced library applies any more, not even the steps of ⌘Z.
    private func startOver() {
        selection = .all
        resetList()
        expanded = []
        history = UndoHistory()
    }

    /// After a refresh the list shows only unread articles, except those of the entry under the cursor: nothing
    /// changes under it.
    private func dropReadEntries() {
        keptArticles = cursor.flatMap { entry($0.entryID) }.map { Set($0.articles.map(\.id)) } ?? []
        unsaved = unsaved.filter { .savedArticle($0.key) == cursor?.entryID }
    }

    /// A removed feed, folder or topic can't stay selected; All is selected instead.
    private func dropRemovedSelection() {
        if !model.library.contains(selection) {
            selection = .all
        }
    }

    /// When the AI puts a loose article into a story, the list entry changes its ID. The cursor follows the article:
    /// into the expanded story when that shows several articles, else onto the story's row. Nothing is read by that.
    private func followArticlesIntoStories() {
        guard let cursor, case .loose(let article) = cursor.entryID,
            let storyID = model.library.storyIDsByArticle()[article]
        else { return }
        let id = StoryEntry.ID.story(storyID)
        if entry(id)?.isMultiArticle == true {
            expanded.insert(id)
            self.cursor = .article(id, article)
        } else {
            self.cursor = .story(id)
        }
    }
}
