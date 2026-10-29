import Foundation

@testable import Feedini

/// Holds a library for the AI queues, without the rest of the app.
@MainActor
final class TestLibraryHost: LibraryHost {
    var library: Library

    init(_ library: Library) {
        self.library = library
    }

    func update(_ change: (inout Library) -> Void) {
        change(&library)
    }
}

extension ClaudeLocator {
    /// A locator that finds claude in `~/.local/bin` (`found`) or nowhere.
    static func stub(found: Bool = true) -> ClaudeLocator {
        ClaudeLocator(homeDirectory: "/Users/me", searchPath: nil) { _ in found }
    }
}

extension AppModel {
    /// A model over a store in a new temporary directory and defaults of its own, not loaded (no refresh, no AI).
    static func test() -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appending(path: "feedini-\(UUID().uuidString)")
        return AppModel(
            preferences: Preferences(defaults: UserDefaults(suiteName: "feedini-tests-\(UUID().uuidString)")!),
            store: LibraryStore(fileURL: directory.appending(path: "library.json")))
    }
}
