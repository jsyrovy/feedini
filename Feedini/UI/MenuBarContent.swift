import SwiftUI

/// The menu bar item: 🎩 with the number of unread stories.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let unread = StoryList.unreadCounts(model.entries).all
        Text(verbatim: model.preferences.showsUnreadCount && unread > 0 ? "🎩 \(unread)" : "🎩")
            .accessibilityLabel(unread == 1 ? "Feedini, 1 unread story" : "Feedini, \(unread) unread stories")
    }
}

/// The menu of the menu bar item.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let unread = StoryList.unreadCounts(model.entries).all
        Text(unread == 1 ? "1 unread story" : "\(unread) unread stories")
        Button("Open Feedini") {
            AppDelegate.mainWindowIsOpen(true)
            openWindow(id: FeediniApp.mainWindowID)
        }
        .keyboardShortcut("o")
        Divider()
        Button("Refresh Now") { model.refreshNow() }
            .keyboardShortcut("r")
            .disabled(model.library.feeds.isEmpty || model.isRefreshing)
        Text(refreshState)
        if let message = model.aiStatus.message {
            Text(message)
        }
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit Feedini") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var refreshState: String {
        if model.isRefreshing {
            return "Refreshing…"
        }
        guard let lastRefresh = model.lastRefresh else { return "Not refreshed yet" }
        return "Updated at \(lastRefresh.formatted(date: .omitted, time: .shortened))"
    }
}
