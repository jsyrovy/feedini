import SwiftUI

/// The stories and articles of a sidebar item. Opening a row reads it (`EntryLink`); a swipe marks it read or unread
/// (leading) or saves it (trailing). Read rows stay until the list is left or refreshed.
struct StoryListScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(ReadingSession.self) private var session
    let selection: SidebarSelection
    @State private var isConfirmingMarkAll = false
    @State private var isSavingLink = false

    var body: some View {
        let entries = session.selection == selection ? session.entries : []
        List(entries) { entry in
            EntryLink(row: .story(entry.id), link: entry.singleArticle(at: .story(entry.id))?.link) {
                EntryRow(entry: entry)
            }
            .swipeActions(edge: .leading) {
                Button(entry.isRead ? "Unread" : "Read", systemImage: entry.isRead ? "circle.fill" : "checkmark.circle")
                {
                    session.toggleRead(.story(entry.id))
                }
                .tint(.accentColor)
            }
            .swipeActions(edge: .trailing) {
                if let article = entry.singleArticle(at: .story(entry.id)) {
                    Button(
                        article.isSaved ? "Unsave" : "Save",
                        systemImage: article.isSaved ? "bookmark.slash" : "bookmark"
                    ) {
                        session.toggleSaved(.story(entry.id))
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshNowAndWait() }
        .toolbar {
            if selection == .saved {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save Link", systemImage: "plus") { isSavingLink = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis.circle") {
                    ListOrderPicker(preferences: model.preferences)
                    if selection != .saved {
                        Button("Mark All as Read", systemImage: "checkmark.circle") { isConfirmingMarkAll = true }
                            .disabled(entries.allSatisfy(\.isRead))
                    }
                }
            }
        }
        .sheet(isPresented: $isSavingLink) {
            SaveLinkSheet()
                .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Mark everything here as read?", isPresented: $isConfirmingMarkAll, titleVisibility: .visible
        ) {
            Button("Mark All as Read") { session.markAllRead() }
        }
        .overlay {
            if entries.isEmpty && model.isLoaded {
                ContentUnavailableView(
                    selection == .saved ? "Nothing Saved" : "All Read",
                    systemImage: selection == .saved ? "bookmark" : "checkmark.circle",
                    description: Text(
                        selection == .saved
                            ? "Swipe left on an article to save it for later." : "New articles show here."))
            }
        }
        .onAppear {
            if session.selection != selection {
                session.selection = selection
            }
        }
    }

    private var title: String {
        let library = model.library
        return switch selection {
        case .all: "All"
        case .saved: "Saved"
        case .topic(let id): library.topics[id]?.name ?? "Topic"
        case .folder(let id): library.folder(id)?.name ?? "Folder"
        case .feed(let id): library.feed(id)?.title ?? "Feed"
        }
    }
}

/// A row that opens an item: its detail, or – when Settings show articles as Web Page – an article's source page in
/// Safari's view over the list, reading the article; touching and holding the row offers its text (the detail).
struct EntryLink<Label: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(ReadingSession.self) private var session
    @Environment(Navigation.self) private var navigation
    let row: ListRow
    /// The source page of the article the row stands for, `nil` for a story with several articles (it has no single
    /// page) or an article without a link.
    let link: URL?
    @ViewBuilder let label: Label

    var body: some View {
        if model.preferences.articleView == .webPage, let link {
            Button {
                session.open(row)
                navigation.page = link
            } label: {
                label
            }
            // Like a navigation link, not an accent-colored button.
            .tint(.primary)
            .contextMenu {
                Button("Show Text", systemImage: "text.alignleft") { navigation.path.append(.entry(row)) }
            }
        } else {
            NavigationLink(value: Route.entry(row)) {
                label
            }
        }
    }
}

/// A story or an article in the list: unread dot, title, sources, age; a bookmark when saved.
struct EntryRow: View {
    @Environment(AppModel.self) private var model
    let entry: StoryEntry

    var body: some View {
        let sources = entry.sourceArticles.compactMap(model.library.sourceTitle(of:))
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(entry.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.body.weight(entry.isRead ? .regular : .semibold))
                    .foregroundStyle(entry.isRead ? .secondary : .primary)
                    .lineLimit(3)
                if entry.isMultiArticle, let summary = entry.summary {
                    Text(summary.text.replacing("- ", with: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 4) {
                    if entry.containsSaved {
                        Image(systemName: "bookmark.fill").foregroundStyle(.orange)
                    }
                    if entry.isSavedLink {
                        Image(systemName: "link")
                    }
                    Text(meta(sources: sources))
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func meta(sources: [String]) -> String {
        let count = entry.articles.count > 1 ? "\(entry.articles.count) articles" : nil
        let source = sources.count > 2 ? "\(sources[0]) +\(sources.count - 1)" : sources.joined(separator: ", ")
        let age = RelativeTime.short(entry.date, now: .now)
        // The age first, as on the Mac: a long feed name is cut, never the age.
        return [age, count, source].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
