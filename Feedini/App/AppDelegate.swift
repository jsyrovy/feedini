import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let reader: Reader

    override init() {
        reader = Reader(model: model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await model.start() }
        // After sleep the feeds are refreshed right away instead of at the end of the interval.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [model] _ in
            MainActor.assumeIsolated { model.refreshNow() }
        }
        // ⌘Z takes back reading only while the main window is the key window (`UndoCommands`).
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [reader] _ in
                MainActor.assumeIsolated {
                    reader.isMainWindowKey = NSApp.keyWindow.map(Self.isMainWindow) ?? false
                }
            }
        }
    }

    /// The window of the `Window` scene with `FeediniApp.mainWindowID`.
    private static func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix(FeediniApp.mainWindowID) == true
    }

    /// Closing the window keeps Feedini running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// With the main window open Feedini is a regular app with a Dock icon; without it, only the menu bar item stays.
    static func mainWindowIsOpen(_ isOpen: Bool) {
        NSApp.setActivationPolicy(isOpen ? .regular : .accessory)
        if isOpen {
            NSApp.activate()
        }
    }

    /// Saves pending changes before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
