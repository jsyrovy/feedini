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
