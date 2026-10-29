import SwiftUI

/// The stories of the sidebar selection, driven by the keyboard (`KeyboardNavigation`).
struct StoryListView: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader
    @FocusState private var isFocused: Bool

    var body: some View {
        let rows = reader.rows
        ScrollViewReader { proxy in
            List(selection: cursor) {
                ForEach(rows, id: \.self) { row in
                    if let entry = reader.entry(row.entryID) {
                        rowView(row, entry: entry)
                            .tag(row)
                            .id(row)
                    }
                }
            }
            .focused($isFocused)
            .onKeyPress(phases: .down) { press in
                guard let key = Self.listKey(press) else { return .ignored }
                return reader.handle(key) ? .handled : .ignored
            }
            .contextMenu(forSelectionType: ListRow.self) { rows in
                if let row = rows.first {
                    Button("Mark as Read / Unread") { reader.toggleRead(row) }
                }
            } primaryAction: { rows in
                if rows.first != nil {
                    reader.handle(.open)
                }
            }
            .onChange(of: reader.cursor) { _, cursor in
                if let cursor {
                    proxy.scrollTo(cursor)
                }
            }
            .onChange(of: reader.listFocusRequests) {
                isFocused = true
            }
            .onAppear { isFocused = true }
        }
        .overlay {
            if rows.isEmpty && model.isLoaded && !model.library.feeds.isEmpty {
                ContentUnavailableView(
                    "All Read", systemImage: "checkmark.circle", description: Text("No unread articles."))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar()
        }
    }

    @ViewBuilder
    private func rowView(_ row: ListRow, entry: StoryEntry) -> some View {
        switch row {
        case .story:
            StoryRow(entry: entry, isExpanded: reader.expanded.contains(entry.id)) {
                reader.toggleExpanded(entry.id)
            }
        case .article(_, let articleID):
            if let article = entry.article(articleID) {
                ArticleRow(article: article, isNew: entry.newArticleIDs.contains(articleID))
            }
        }
    }

    private var cursor: Binding<ListRow?> {
        Binding(get: { reader.cursor }, set: { reader.visit($0) })
    }

    /// Plain keys only; with ⌘, ⌃ or ⌥ the key goes to the menus.
    private static func listKey(_ press: KeyPress) -> ListKey? {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        let shift = press.modifiers.contains(.shift)
        switch press.key {
        case .downArrow: return .next
        case .upArrow: return .previous
        case .rightArrow: return .expand
        case .leftArrow: return .collapse
        case .escape: return .escape
        case .return: return shift ? .openOther : .open
        default: break
        }
        switch press.characters.lowercased() {
        case "j": return .next
        case "k": return .previous
        case "l": return .expand
        case "h": return .collapse
        case "v": return shift ? .openOther : .open
        case "m": return .toggleRead
        case "r": return .refresh
        case "a": return shift ? .markAllRead : nil
        default: return nil
        }
    }
}

/// Refresh status under the list.
private struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            if model.isRefreshing {
                ProgressView().controlSize(.mini)
                Text("Refreshing…")
            } else if let lastRefresh = model.lastRefresh {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(RelativeTime.updated(lastRefresh, now: context.date))
                }
            } else if let problem = model.loadProblem {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(problem).lineLimit(1).help(problem)
            }
            Spacer()
            if let message = model.aiStatus.message {
                if model.aiStatus.isWorking {
                    Image(systemName: "sparkles")
                } else {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Text(message).lineLimit(1).truncationMode(.tail).help(message)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }
}
