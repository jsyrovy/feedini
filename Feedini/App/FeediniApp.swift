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
            CommandGroup(after: .toolbar) {
                Button("Refresh Now") { appDelegate.model.refreshNow() }
                    .keyboardShortcut("r")
            }
        }

        Settings {
            SettingsView()
                .environment(appDelegate.model)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.model)
        } label: {
            Text(verbatim: "🎩")
                .accessibilityLabel("Feedini")
        }
    }
}

private struct TestHostApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
