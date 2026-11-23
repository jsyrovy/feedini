import AppKit
import Observation

/// The state of the main window on top of the shared `ReadingSession` (selection, cursor, expanded stories, kept
/// articles, undo): the source page or page text shown in the detail, the sheets and the keyboard focus. Carries out
/// the keyboard decisions of `KeyboardNavigation`.
@MainActor
@Observable
final class Reader {
    let session: ReadingSession
    let services: MacServices
    var model: AppModel { services.model }

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
    /// Whether the main window is the key window, where ⌘Z takes back reading and saving (`UndoCommands`).
    var isMainWindowKey = false

    init(services: MacServices) {
        self.services = services
        session = ReadingSession(model: services.model)
        session.onCursorMove = { [weak self] in self?.shown = nil }
    }

    // MARK: The session

    /// The sidebar selection; changing it drops read entries from the list.
    var selection: SidebarSelection {
        get { session.selection }
        set { session.selection = newValue }
    }
    var cursor: ListRow? { session.cursor }
    var expanded: Set<StoryEntry.ID> { session.expanded }
    var keptArticles: Set<Article.ID> { session.keptArticles }
    var history: UndoHistory { session.history }
    var entries: [StoryEntry] { session.entries }
    var cursorArticle: Article? { session.cursorArticle }

    var rows: [ListRow] {
        ListRow.rows(entries, expanded: expanded)
    }

    func entry(_ id: StoryEntry.ID) -> StoryEntry? {
        session.entry(id)
    }

    /// Moves the cursor onto a row, which reads it (`ReadRules`).
    func visit(_ row: ListRow?) {
        session.visit(row)
    }

    func toggleRead(_ row: ListRow) {
        session.toggleRead(row)
    }

    /// S: saves the row's article for later, or removes it from Saved.
    func toggleSaved(_ row: ListRow) {
        session.toggleSaved(row)
    }

    func toggleExpanded(_ id: StoryEntry.ID) {
        session.toggleExpanded(id)
    }

    var undoName: String? { session.undoName }
    var redoName: String? { session.redoName }

    /// ⌘Z: takes back the last step of reading or saving.
    func undo() {
        session.undo()
    }

    /// ⇧⌘Z: does the step taken back last again.
    func redo() {
        session.redo()
    }

    var opensInWindow: Bool {
        model.preferences.pageOpening == .window
    }

    // MARK: Keys

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
            session.expanded.insert(id)
        case .collapse(let id):
            session.expanded.remove(id)
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
        case .saveWithSummary(let row):
            saveWithSummary(row)
        case .refresh:
            model.refreshNow()
        case .markAllRead:
            session.markAllRead()
        }
        return true
    }

    /// Shift+S: saves the row's article unless it is saved and prepares the TL;DR of its source page (when it has a
    /// link) in the background; the detail stays as it is.
    func saveWithSummary(_ row: ListRow) {
        guard let article = entry(row.entryID)?.singleArticle(at: row) else { return }
        if !article.isSaved {
            toggleSaved(row)
        }
        if article.link != nil {
            services.preparePage(article.id)
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
        services.reloadPage(id)
    }

    /// T: from the source page in the window it goes back to the text, where the summary shows.
    func summarizePage(_ id: Article.ID) {
        if pageArticle != nil {
            closePage()
        }
        services.summarizePage(id)
    }
}
