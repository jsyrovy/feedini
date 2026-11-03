import SwiftUI

/// The menu bar item: the pixel-art hat (a template image) with the number of unread stories.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let unread = model.unreadCounts.all
        HStack {
            Image(.menuBarIcon)
            if model.preferences.showsUnreadCount && unread > 0 {
                Text(verbatim: "\(unread)")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Feedini, \(unreadStories(unread))")
    }
}

/// The menu of the menu bar item.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(unreadStories(model.unreadCounts.all))
        Button("Open Feedini") {
            AppDelegate.mainWindowIsOpen(true)
            openWindow(id: FeediniApp.mainWindowID)
        }
        .keyboardShortcut("o")
        SaveLinkButton(reader: reader)
        Divider()
        Button("Refresh Now") { model.refreshNow() }
            .keyboardShortcut("r")
            .disabled(model.library.feeds.isEmpty || model.isRefreshing)
        Text(refreshState)
        Text(aiState)
        if let problem = model.backups.problem {
            Text("Backup: \(problem)")
        }
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit Feedini") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Always shown, so the menu tells what the AI is doing even when it is idle.
    private var aiState: String {
        if let message = model.aiStatus.message {
            return message
        }
        return model.aiStatus.state == .off ? "AI: off" : "AI: ready"
    }

    private var refreshState: String {
        if model.isRefreshing {
            return "Refreshing…"
        }
        guard let lastRefresh = model.lastRefresh else { return "Not refreshed yet" }
        return "Updated at \(lastRefresh.formatted(date: .omitted, time: .shortened))"
    }
}

/// "1 unread story", "5 unread stories".
private func unreadStories(_ count: Int) -> String {
    count == 1 ? "1 unread story" : "\(count) unread stories"
}
