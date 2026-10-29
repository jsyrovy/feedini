import SwiftUI

/// The menu of the menu bar item.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Feedini") {
            NSApp.activate()
            openWindow(id: FeediniApp.mainWindowID)
        }
        Divider()
        Button("Quit Feedini") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
