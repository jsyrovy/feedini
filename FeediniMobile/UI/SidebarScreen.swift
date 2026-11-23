import SwiftUI

/// All, Saved, the topics (most unread first), the folders with their feeds and the feeds in no folder, with unread
/// counts.
struct SidebarScreen: View {
    @Environment(AppModel.self) private var model
    @Binding var isShowingSettings: Bool

    var body: some View {
        let counts = model.unreadCounts
        let library = model.library
        let topics = StoryList.topics(in: library, counts: counts)
        let feeds = Dictionary(grouping: library.feedsByTitle, by: \.folderID)
        List {
            Section {
                item("All", systemImage: "tray.full", .all, count: counts.all)
                item("Saved", systemImage: "bookmark", .saved, count: counts.saved)
            }
            if !topics.isEmpty {
                Section("Topics") {
                    ForEach(topics) { topic in
                        item(
                            topic.name, systemImage: "number", .topic(topic.id),
                            count: counts.count(for: .topic(topic.id)))
                    }
                }
            }
            ForEach(library.folders) { folder in
                Section {
                    item(
                        folder.name, systemImage: "folder", .folder(folder.id),
                        count: counts.count(for: .folder(folder.id)))
                    ForEach(feeds[folder.id] ?? []) { feed in
                        feedItem(feed, count: counts.count(for: .feed(feed.id)))
                    }
                }
            }
            if let loose = feeds[nil], !loose.isEmpty {
                Section(library.folders.isEmpty ? "Feeds" : "Other Feeds") {
                    ForEach(loose) { feed in
                        feedItem(feed, count: counts.count(for: .feed(feed.id)))
                    }
                }
            }
        }
        .navigationTitle("Feedini")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
            }
        }
        .refreshable { await model.refreshNowAndWait() }
        .overlay {
            if model.isLoaded && library.feeds.isEmpty && library.folders.isEmpty {
                ContentUnavailableView {
                    Label("No Feeds", systemImage: "dot.radiowaves.up.forward")
                } description: {
                    Text("Add feeds by their address in Settings.")
                } actions: {
                    Button("Open Settings") { isShowingSettings = true }
                }
            }
        }
    }

    private func item(_ title: String, systemImage: String, _ selection: SidebarSelection, count: Int) -> some View {
        NavigationLink(value: Route.list(selection)) {
            Label(title, systemImage: systemImage)
                .badge(count)
        }
    }

    private func feedItem(_ feed: Feed, count: Int) -> some View {
        NavigationLink(value: Route.list(.feed(feed.id))) {
            Label {
                Text(feed.title).lineLimit(1)
            } icon: {
                Image(systemName: feed.lastError == nil ? "dot.radiowaves.up.forward" : "exclamationmark.triangle")
                    .foregroundStyle(feed.lastError == nil ? Color.accentColor : .orange)
            }
            .badge(count)
        }
    }
}
