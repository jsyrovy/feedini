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
        /// The source page in the window (V, or the preferred view).
        case page(Article.ID)
        /// The text of the source page (P, or the preferred view).
        case preview(Article.ID)
    }

    /// Set on every move onto an article as `Preferences.articleView` says (`nil`: the feed text). Every change ends
    /// the wait for the cursor to settle: a wait belongs to what was shown.
    private(set) var shown: Shown? {
        didSet { stopWaiting() }
    }
    /// The article whose page the preferred view loads once the cursor has stayed on it for `settleDelay`, so
    /// walking the list with J/K doesn't load the page of every article it passes. The detail shows that it loads.
    private(set) var waitingArticle: Article.ID?
    /// The article the preferred view was shown for (`nil`: no article under the cursor).
    @ObservationIgnored private var viewArticle: Article.ID?
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

    /// How long the cursor stays on an article before the preferred view loads its page.
    static let settleDelay: Duration = .milliseconds(500)
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var settling: Task<Void, Never>?

    init(
        services: MacServices,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.services = services
        self.sleep = sleep
        session = ReadingSession(model: services.model)
        session.onCursorMove = { [weak self] in self?.cursorMoved() }
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

    /// The cursor was set, or the list started over. Undo sets it onto the article it is on already (its row, or the
    /// story row the AI moved it to): then the detail stays as the user left it (a page opened with V, the feed text
    /// after Esc), and nothing loads again.
    private func cursorMoved() {
        let article = cursorArticle?.id
        guard article == nil || article != viewArticle else { return }
        viewArticle = article
        showPreferredView()
    }

    /// What the detail shows on the article the cursor moved onto (`Preferences.articleView`). A page that isn't
    /// stored loads once the cursor stays.
    private func showPreferredView() {
        let view = preferredView
        shown = view
        switch view {
        case .page(let id):
            loadWhenSettled(id)
        case .preview(let id) where !model.library.pageTextIDs.contains(id):
            loadWhenSettled(id)
        case .preview, nil:
            break
        }
    }

    /// The feed text, or the page text or source page of the article under the cursor, if it has a link. A saved
    /// link shows its page text anyway; a story with several articles has no page.
    private var preferredView: Shown? {
        guard let article = cursorArticle, article.link != nil else { return nil }
        switch model.preferences.articleView {
        case .pageText where !article.isSavedLink:
            return .preview(article.id)
        case .feedText, .pageText:
            return nil
        case .webPage:
            // Unlike V, it keeps the stored page text: J/K would otherwise throw away what P, T and Shift+S loaded.
            return .page(article.id)
        }
    }

    /// Loads the page of the preferred view once the cursor has stayed on the article for `settleDelay`.
    private func loadWhenSettled(_ id: Article.ID) {
        waitingArticle = id
        settling = Task { [weak self, sleep] in
            guard (try? await sleep(Self.settleDelay)) != nil else { return }
            guard let self, waitingArticle == id else { return }
            waitingArticle = nil
            if previewArticle == id {
                model.loadPage(id)
            }
        }
    }

    private func stopWaiting() {
        settling?.cancel()
        settling = nil
        waitingArticle = nil
    }

    /// Waits until the page of the preferred view is loading (tests).
    func waitUntilSettled() async {
        await settling?.value
    }

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
        focusList()
    }

    /// Gives the keyboard focus to the story list.
    func focusList() {
        listFocusRequests += 1
    }

    /// A double click on a row opens it like V / Enter, but never closes the page it shows in the window: a page the
    /// preferred view waits to load shows at once.
    func openOnDoubleClick() {
        guard opensInWindow, let pageArticle, pageArticle == cursorArticle?.id else {
            handle(.open)
            return
        }
        stopWaiting()
    }

    /// P: the page text instead of the feed text (loaded unless stored), or the feed text again – also when the page
    /// text is the preferred view. From the source page it goes straight to the text.
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
