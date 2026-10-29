import SwiftUI

/// All, the topics (most unread first) and the feeds, with unread counts.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader

    var body: some View {
        let counts = model.unreadCounts
        let topics = StoryList.topics(in: model.library, counts: counts)
        let feeds = model.library.feeds.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
                ForEach(feeds) { feed in
                    Label {
                        Text(feed.title)
                    } icon: {
                        Image(
                            systemName: feed.lastError == nil ? "dot.radiowaves.up.forward" : "exclamationmark.triangle"
                        )
                        .foregroundStyle(feed.lastError == nil ? Color.accentColor : .orange)
                    }
                    .badge(counts.count(for: .feed(feed.id)))
                    .tag(SidebarSelection.feed(feed.id))
                    .help(feed.lastError ?? feed.url.absoluteString)
                }
            }
        }
        .overlay {
            if model.isLoaded && feeds.isEmpty {
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
}
