import SwiftUI

/// All, the topics (most unread first), the folders (in their order) with their feeds, and the feeds in no folder,
/// with unread counts. Feeds and folders are moved by dragging (`SidebarDrag`) or from the context menu.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader
    @State private var naming: FolderNaming?

    var body: some View {
        let counts = model.unreadCounts
        let topics = StoryList.topics(in: model.library, counts: counts)
        let library = model.library
        let feeds = Dictionary(grouping: library.feedsByTitle, by: \.folderID)
        List(selection: selection) {
            Label("All", systemImage: "tray.full")
                .badge(counts.all)
                .tag(SidebarSelection.all)
            if !topics.isEmpty {
                Section("Topics") {
                    ForEach(topics) { topic in
                        Label(topic.name, systemImage: "number")
                            .badge(counts.count(for: .topic(topic.id)))
                            .tag(SidebarSelection.topic(topic.id))
                            .help(topic.description)
                    }
                }
            }
            Section("Feeds") {
                ForEach(library.folders) { folder in
                    DisclosureGroup(isExpanded: isExpanded(folder.id)) {
                        ForEach(feeds[folder.id] ?? []) { feed in
                            FeedRow(feed: feed, count: counts.count(for: .feed(feed.id)))
                        }
                    } label: {
                        Label(folder.name, systemImage: "folder")
                            .lineLimit(1)
                            .badge(counts.count(for: .folder(folder.id)))
                            .tag(SidebarSelection.folder(folder.id))
                            .modifier(Dragging(item: .folder(folder.id)))
                    }
                }
                ForEach(feeds[nil] ?? []) { feed in
                    FeedRow(feed: feed, count: counts.count(for: .feed(feed.id)))
                }
            }
        }
        .contextMenu(forSelectionType: SidebarSelection.self) { items in
            menu(for: items)
        }
        .sheet(item: $naming) { naming in
            FolderNameSheet(naming: naming)
        }
        .overlay {
            if model.isLoaded && library.feeds.isEmpty && library.folders.isEmpty {
                ContentUnavailableView {
                    Label("No Feeds", systemImage: "dot.radiowaves.up.forward")
                } description: {
                    Text("Add feeds in Settings.")
                } actions: {
                    SettingsLink { Text("Open Settings") }
                }
            }
        }
    }

    private var selection: Binding<SidebarSelection?> {
        Binding(get: { reader.selection }, set: { reader.selection = $0 ?? .all })
    }

    private func isExpanded(_ folder: Folder.ID) -> Binding<Bool> {
        Binding(
            get: { !model.preferences.collapsedFolders.contains(folder) },
            set: { expanded in
                if expanded {
                    model.preferences.collapsedFolders.remove(folder)
                } else {
                    model.preferences.collapsedFolders.insert(folder)
                }
            })
    }

    @ViewBuilder
    private func menu(for items: Set<SidebarSelection>) -> some View {
        switch items.count == 1 ? items.first : nil {
        case .folder(let id):
            let folders = model.library.folders
            Button("Rename…") { naming = FolderNaming(folder: id) }
            Button("Move Up") { model.moveFolder(id, by: -1) }
                .disabled(folders.first?.id == id)
            Button("Move Down") { model.moveFolder(id, by: 1) }
                .disabled(folders.last?.id == id)
            Divider()
            Button("Delete Folder") { model.removeFolder(id) }
            Divider()
            Button("New Folder…") { naming = FolderNaming() }
        case .feed(let id):
            MoveToFolderMenu(model: model, feeds: [id]) { naming = $0 }
        default:
            Button("New Folder…") { naming = FolderNaming() }
        }
    }
}

/// A feed: its state (an error is orange) and unread count; it can be dragged into a folder.
private struct FeedRow: View {
    let feed: Feed
    let count: Int

    var body: some View {
        Label {
            Text(feed.title)
        } icon: {
            Image(systemName: feed.lastError == nil ? "dot.radiowaves.up.forward" : "exclamationmark.triangle")
                .foregroundStyle(feed.lastError == nil ? Color.accentColor : .orange)
        }
        .badge(count)
        .tag(SidebarSelection.feed(feed.id))
        .help(feed.lastError ?? feed.url.absoluteString)
        .modifier(Dragging(item: .feed(feed.id)))
    }
}

/// Lets a feed or folder row be dragged, and other feeds and folders be dropped on it.
private struct Dragging: ViewModifier {
    @Environment(AppModel.self) private var model
    let item: SidebarSelection

    func body(content: Content) -> some View {
        if let text = SidebarDrag.text(for: item) {
            content
                .draggable(text)
                .dropDestination(for: String.self) { texts, _ in
                    guard let dragged = texts.first.flatMap(SidebarDrag.item(from:)) else { return false }
                    return model.drop(dragged, onto: item)
                }
        } else {
            content
        }
    }
}
