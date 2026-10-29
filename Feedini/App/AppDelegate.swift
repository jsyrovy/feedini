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
