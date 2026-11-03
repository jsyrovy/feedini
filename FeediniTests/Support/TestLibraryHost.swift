import Foundation

@testable import Feedini

/// Holds a library for the AI queues, without the rest of the app.
@MainActor
final class TestLibraryHost: LibraryHost {
    struct StoreFailure: Error {}

    var library: Library
    /// The stored page texts (`library.pageTextIDs` lists them).
    var pageTexts: [Article.ID: String] = [:]
    /// Storing a page text fails while set.
    var failsStoringPageTexts = false

    init(_ library: Library) {
        self.library = library
    }

    func update(_ change: (inout Library) -> Void) {
        change(&library)
    }

    /// The stored page text of the article, as `pageText` gives it.
    func storedText(_ id: Article.ID) -> String? {
        library.pageTextIDs.contains(id) ? pageTexts[id] : nil
    }

    func pageText(_ id: Article.ID) async -> String? {
        storedText(id)
    }

    func storePageText(_ text: String, for id: Article.ID) async throws {
        guard !failsStoringPageTexts else { throw StoreFailure() }
        pageTexts[id] = text
        library.pageTextIDs.insert(id)
    }
}

extension ClaudeLocator {
    /// A locator that finds claude in `~/.local/bin` (`found`) or nowhere.
    static func stub(found: Bool = true) -> ClaudeLocator {
        ClaudeLocator(homeDirectory: "/Users/me", searchPath: nil) { _ in found }
    }
}

extension AppModel {
    /// A model over a store in a new temporary directory and defaults of its own, not loaded (no refresh, no AI
    /// queues running). Claude calls and source pages go to the given fakes.
    static func test(
        runner: FakeCommandRunner = FakeCommandRunner([]), extractor: FakePageExtractor = FakePageExtractor()
    ) -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appending(path: "feedini-\(UUID().uuidString)")
        return AppModel(
            preferences: Preferences(defaults: UserDefaults(suiteName: "feedini-tests-\(UUID().uuidString)")!),
            store: LibraryStore(fileURL: directory.appending(path: "library.json")), claudeRunner: runner,
            claudeLocator: .stub(), pageExtractor: extractor)
    }
}
