import SwiftUI

/// Entry point. The unit test bundle is hosted by the app; under tests an empty app runs instead of Feedini, so no
/// window, refresh or menu bar item is started and the real app needs no test guards.
@main
enum FeediniMain {
    @MainActor
    static func main() {
        if RuntimeEnvironment.isRunningTests {
            TestHostApp.main()
        } else {
            FeediniApp.main()
        }
    }
}

struct FeediniApp: App {
    /// The ID of the main window, for `openWindow(id:)`.
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Feedini", id: Self.mainWindowID) {
            MainWindow()
                .environment(appDelegate.model)
                .environment(appDelegate.reader)
        }
        .commands {
            CommandGroup(after: .importExport) {
                BackupCommands(model: appDelegate.model, reader: appDelegate.reader)
            }
            CommandGroup(replacing: .undoRedo) {
                UndoCommands(reader: appDelegate.reader)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh Now") { appDelegate.model.refreshNow() }
                    .keyboardShortcut("r")
            }
            // The default Help item has nothing to show. No key equivalent: a plain ? would fire in text fields too, and
            // ⌘? searches the Help menu.
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { appDelegate.reader.isShowingShortcuts = true }
            }
            #if DEBUG
                DebugCommands(model: appDelegate.model)
            #endif
        }

        Settings {
            SettingsView()
                .environment(appDelegate.model)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
    }
}

private struct TestHostApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
