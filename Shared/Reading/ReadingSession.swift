import Foundation
import Observation

/// The reading state of a window, shared by both apps: the sidebar selection, the row being read (the cursor),
/// expanded stories, the articles read while the list is shown and the undo history of reading and saving. Carries
/// out the read rules; the Mac's `Reader` adds the keys and the detail on top.
@MainActor
@Observable
final class ReadingSession {
    let model: AppModel

    /// The sidebar selection; changing it drops read entries from the list.
    var selection: SidebarSelection = .all {
        didSet {
            guard selection != oldValue else { return }
            resetList()
        }
    }
    private(set) var cursor: ListRow?
    /// Stories whose articles are shown one by one (expanded in the list on the Mac).
    var expanded: Set<StoryEntry.ID> = []
    /// Articles read while the list is shown; they stay in it (and in their stories) until the selection changes or a
    /// refresh.
    private(set) var keptArticles: Set<Article.ID> = []
    /// Articles removed from Saved while it was shown, with their save dates: they stay in their place like articles
    /// read there.
    private(set) var unsaved: [Article.ID: Date] = [:]
    /// Reading and saving for undo; it lives as long as the app, not the window.
    private(set) var history = UndoHistory()
    /// Called when the cursor moves to another row or the list starts over (the Mac closes the page it shows).
    @ObservationIgnored var onCursorMove: (@MainActor () -> Void)?

    init(model: AppModel) {
        self.model = model
        model.onRefresh = { [weak self] in self?.dropReadEntries() }
        model.onLibraryChange = { [weak self] in
            self?.dropRemovedSelection()
            self?.followArticlesIntoStories()
        }
        model.onRestore = { [weak self] in self?.startOver() }
        model.onRemoteChange = { [weak self] old, new in self?.keepArticlesReadElsewhere(old, new) }
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

    /// The entry with the articles it shows (`StoryEntry.visible(keeping:)`); `nil` when it shows none. Saved shows
    /// its articles read or not.
    func entry(_ id: StoryEntry.ID) -> StoryEntry? {
        model.entry(id)?.visible(keeping: keptArticles)
    }

    /// The article under the cursor: the article row, or the only article of a story.
    var cursorArticle: Article? {
        guard let cursor else { return nil }
        return entry(cursor.entryID)?.singleArticle(at: cursor)
    }

    // MARK: Reading

    /// Moves the cursor onto a row, which reads it (`ReadRules`).
    func visit(_ row: ListRow?) {
        guard row != cursor else { return }
        move(to: row)
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

    func toggleRead(_ row: ListRow) {
        guard let entry = entry(row.entryID) else { return }
        switch ReadRules.toggle(row, of: entry) {
        case .markRead(let ids):
            keptArticles.formUnion(ids)
            recording("Mark as Read", articles: ids, row: row) { model.markRead(ids) }
        case .markUnread(let ids): recording("Mark as Unread", articles: ids, row: row) { model.markUnread(ids) }
        }
    }

    /// Saves the row's article for later, or removes it from Saved (where it stays until the selection changes). The
    /// row of a story with several articles has none.
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

    /// Everything in the current selection; the list empties. Saved isn't marked read: it is a list to come back to.
    func markAllRead() {
        guard selection != .saved else { return }
        let entries = entries
        let ids = entries.flatMap { $0.articles.filter { !$0.isRead }.map(\.id) }
        keptArticles = []
        move(to: nil)
        recording("Mark All as Read", articles: ids, row: entries.first.map { .story($0.id) }) { model.markRead(ids) }
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

    private func move(to row: ListRow?) {
        cursor = row
        onCursorMove?()
    }

    // MARK: Undo

    var undoName: String? { history.undoName }
    var redoName: String? { history.redoName }

    /// Takes back the last step of reading or saving that still has something to take back, and shows its row
    /// without reading it.
    func undo() {
        show(history.undo { model.restore($0) })
    }

    /// Does the step taken back last again.
    func redo() {
        show(history.redo { model.restore($0) })
    }

    /// Changes reading or saving and records the change for undo. The callers only make changes that change
    /// something (they read unread articles, toggle, save what isn't saved).
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
        let rows = ListRow.rows(entries, expanded: expanded)
        guard let target = rows.contains(row) ? row : rows.first(where: { $0 == .story(row.entryID) }) else { return }
        move(to: target)
    }

    // MARK: Refresh

    /// The list was left (iOS: back to the sidebar): coming back shows only what is unread then.
    func leaveList() {
        resetList()
    }

    /// The list of a new selection: no cursor, nothing kept.
    private func resetList() {
        move(to: nil)
        keptArticles = []
        unsaved = [:]
    }

    /// After a restore: nothing of the replaced library applies any more, not even the undo steps.
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

    /// Articles read on another device stay in the list like those read here, so rows don't move under the cursor;
    /// they go when the selection changes or after a refresh.
    private func keepArticlesReadElsewhere(_ old: Library, _ new: Library) {
        guard old.articles != new.articles else { return }
        for (id, article) in new.articles where article.isRead && old.articles[id]?.isRead == false {
            keptArticles.insert(id)
        }
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
            let storyID = model.library.stories.values.first(where: { $0.articleIDs.contains(article) })?.id
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
