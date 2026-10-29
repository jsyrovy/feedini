import SwiftUI

/// The menu of the menu bar item.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Feedini") {
            NSApp.activate()
            openWindow(id: FeediniApp.mainWindowID)
        }
        Button("Refresh Now") { model.refreshNow() }
            .disabled(model.library.feeds.isEmpty)
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Feedini") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
