import Foundation
import Testing

@testable import Feedini

struct LibraryStoreTests {
    private let directory = FileManager.default.temporaryDirectory.appending(
        path: "feedini-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    private var fileURL: URL { directory.appending(path: "library.json") }
    private let sleeper = ManualSleeper()

    private func store() -> LibraryStore {
        LibraryStore(fileURL: fileURL, debounce: .seconds(2), sleep: sleeper.sleep(for:))
    }

    private func sampleLibrary(title: String = "Tech") -> Library {
        let feed = Feed.stub(title)
        return Library(feeds: [feed], articles: [.stub(feed: feed.id)])
    }

    private func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains("unreadable") }
    }

    @Test func loadsAnEmptyLibraryWithoutAFile() async {
        let result = await store().load()
        #expect(result.library == Library())
        #expect(result.problem == nil)
    }

    @Test func savesAfterTheDebounceDelayAndLoadsItBack() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store()
        var sleeps = sleeper.sleeps.makeAsyncIterator()
        let first = sampleLibrary(title: "First")
        let latest = sampleLibrary(title: "Latest")

        await store.save(first)
        #expect(await sleeps.next() == .seconds(2))
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        // A change during the delay is written with it.
        await store.save(latest)
        sleeper.wake()
        await store.flush()

        let result = await LibraryStore(fileURL: fileURL).load()
        #expect(result.library == latest)
        #expect(result.problem == nil)
        let json = try #require(String(data: Data(contentsOf: fileURL), encoding: .utf8))
        #expect(json.contains("\"version\" : 1"))
    }

    @Test func savesPageTextsAndSummaries() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store()
        var sleeps = sleeper.sleeps.makeAsyncIterator()
        var library = sampleLibrary()
        let id = try #require(library.articles.keys.first)
        library.articles[id]?.pageText = "The text of the page."
        library.articles[id]?.pageSummary = PageSummary(
            tldr: "The gist.", details: ["A detail."], language: "en", date: referenceDate)

        await store.save(library)
        _ = await sleeps.next()
        await store.flush()

        #expect(await LibraryStore(fileURL: fileURL).load().library == library)
    }

    /// Files from before page texts have no such fields.
    @Test func articlesWithoutPageTextsAreSavedWithoutTheFields() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store()
        var sleeps = sleeper.sleeps.makeAsyncIterator()
        let library = sampleLibrary()

        await store.save(library)
        _ = await sleeps.next()
        await store.flush()

        let json = try #require(String(data: Data(contentsOf: fileURL), encoding: .utf8))
        #expect(!json.contains("pageText") && !json.contains("pageSummary"))
        #expect(await LibraryStore(fileURL: fileURL).load().library == library)
    }

    @Test func flushWritesAPendingChangeRightAway() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store()
        var sleeps = sleeper.sleeps.makeAsyncIterator()
        let library = sampleLibrary()

        await store.save(library)
        _ = await sleeps.next()
        await store.flush()

        #expect(await LibraryStore(fileURL: fileURL).load().library == library)
    }

    @Test func movesADamagedFileAside() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{\"version\": 1, \"library\": [".utf8).write(to: fileURL)

        let result = await store().load()

        #expect(result.library == Library())
        #expect(result.problem?.hasPrefix("The library file is damaged") == true)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try backups().count == 1)
    }

    @Test func movesAFileFromANewerVersionAside() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{\"version\": 2, \"library\": {}}".utf8).write(to: fileURL)

        let result = await store().load()

        #expect(result.problem == "The library was saved by a newer version of Feedini (schema 2).")
        #expect(try backups().count == 1)
    }
}
