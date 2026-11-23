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
        let folder = Folder(name: "Daily")
        let feed = Feed.stub(title, folder: folder.id)
        return Library(
            feeds: [feed, .stub("Other")], articles: [.stub(feed: feed.id)], folders: [folder, Folder(name: "Empty")])
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
        #expect(json.contains("\"version\" : \(LibraryStore.schemaVersion)"))
    }

    /// Saves the library and waits until it is written; `meanwhile` runs while it waits for the debounce delay.
    private func write(
        _ library: Library, with store: LibraryStore, meanwhile: () async -> Void = {}
    ) async {
        var sleeps = sleeper.sleeps.makeAsyncIterator()
        await store.save(library)
        _ = await sleeps.next()
        await meanwhile()
        sleeper.wake()
        await store.flush()
    }

    private func pageFiles() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "pages").path)) ?? [])
    }

    @Test func savesPageTextsAsFilesOfTheirOwnAndSummariesInTheLibrary() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store()
        var library = sampleLibrary()
        let id = try #require(library.articles.keys.first)
        try await store.storePageText("The text of the page.", for: id)
        library.pageTextIDs = [id]
        library.articles[id]?.pageSummary = PageSummary(
            tldr: "The gist.", details: ["A detail."], language: "en", date: referenceDate)

        await write(library, with: store)

        let loaded = LibraryStore(fileURL: fileURL)
        #expect(await loaded.load().library == library)
        #expect(await loaded.pageText(for: id) == "The text of the page.")
        #expect(await loaded.pageText(for: UUID()) == nil)
        let json = try #require(String(data: Data(contentsOf: fileURL), encoding: .utf8))
        #expect(!json.contains("The text of the page."))
        #expect(json.contains(id.uuidString))
    }

    @Test func deletesAPageTextOnceAWrittenLibraryNoLongerListsIt() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store()
        var library = sampleLibrary()
        let id = try #require(library.articles.keys.first)
        try await store.storePageText("Text.", for: id)
        library.pageTextIDs = [id]
        await write(library, with: store)
        #expect(pageFiles() == ["\(id.uuidString).txt"])

        library.pageTextIDs = []
        await write(library, with: store)

        #expect(pageFiles().isEmpty)
        #expect(await store.pageText(for: id) == nil)
    }

    @Test func aLibraryWaitingToBeWrittenDoesNotDeleteATextStoredMeanwhile() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store()
        var library = sampleLibrary()
        let id = try #require(library.articles.keys.first)
        try await store.storePageText("First.", for: id)
        library.pageTextIDs = [id]
        await write(library, with: store)

        // V forgets the text, P stores it again before the library without it is written.
        library.pageTextIDs = []
        // Checked by reading it below.
        await write(library, with: store) { try? await store.storePageText("Second.", for: id) }
        #expect(await store.pageText(for: id) == "Second.")

        library.pageTextIDs = [id]
        await write(library, with: store)
        #expect(await LibraryStore(fileURL: fileURL).load().library.pageTextIDs == [id])
    }

    @Test func loadingDeletesUnlistedTextsAndForgetsListedOnesWithoutAFile() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store()
        var library = sampleLibrary()
        let id = try #require(library.articles.keys.first)
        let orphan = UUID()
        // Stored, but no written library lists it (a crash before the library was saved).
        try await store.storePageText("Orphan.", for: orphan)
        library.pageTextIDs = [id]
        await write(library, with: store)
        try Data("Not a page text.".utf8).write(to: directory.appending(path: "pages/notes.md"))

        let loaded = await LibraryStore(fileURL: fileURL).load().library

        #expect(loaded.pageTextIDs.isEmpty)
        #expect(pageFiles() == ["notes.md"])
    }

    /// Files from before page files kept the texts in their articles.
    @Test func movesPageTextsOutOfAnOlderFile() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = sampleLibrary()
        var encoded = try #require(
            JSONSerialization.jsonObject(with: LibraryStore.encoder.encode(library)) as? [String: Any])
        encoded["pageTexts"] = nil
        var articles = try #require(encoded["articles"] as? [[String: Any]])
        articles[0]["pageText"] = "The text of the page."
        encoded["articles"] = articles
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["version": 1, "library": encoded]).write(to: fileURL)

        let store = store()
        let loaded = await store.load().library

        // With the article's new ID (schema 3).
        let id = try #require(loaded.articles.keys.first)
        #expect(loaded.pageTextIDs == [id])
        #expect(await store.pageText(for: id) == "The text of the page.")
        // Written without the texts at once.
        let saved = try #require(String(data: Data(contentsOf: fileURL), encoding: .utf8))
        #expect(!saved.contains("The text of the page."))
        #expect(await LibraryStore(fileURL: fileURL).load().library == loaded)
    }

    /// Version 1 saved stories as a whole; their articles are saved instead.
    @Test func loadsSavedStoriesOfSchemaVersion1AsSavedArticles() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
            {"version": 1, "library": {"feeds": [], "pageTexts": [],
             "articles": [
              {"id": "6F9619FF-8B86-D011-B42D-00C04FC964F1", "feedID": "7F9619FF-8B86-D011-B42D-00C04FC964FF",
               "key": "1", "title": "First", "text": "", "firstSeen": "2026-10-29T12:00:00Z"},
              {"id": "6F9619FF-8B86-D011-B42D-00C04FC964F2", "feedID": "7F9619FF-8B86-D011-B42D-00C04FC964FF",
               "key": "2", "title": "Saved before", "text": "", "firstSeen": "2026-10-29T12:00:00Z",
               "savedAt": "2026-10-29T13:00:00Z"},
              {"id": "6F9619FF-8B86-D011-B42D-00C04FC964F3", "feedID": "7F9619FF-8B86-D011-B42D-00C04FC964FF",
               "key": "3", "title": "Not saved", "text": "", "firstSeen": "2026-10-29T12:00:00Z"}],
             "stories": [
              {"id": "8F9619FF-8B86-D011-B42D-00C04FC964F1", "title": "Saved", "newArticleIDs": [],
               "articleIDs": ["6F9619FF-8B86-D011-B42D-00C04FC964F1", "6F9619FF-8B86-D011-B42D-00C04FC964F2",
                 "6F9619FF-8B86-D011-B42D-00C04FC964F9"],
               "savedAt": "2026-10-29T14:00:00Z"},
              {"id": "8F9619FF-8B86-D011-B42D-00C04FC964F2", "title": "Not saved", "newArticleIDs": [],
               "articleIDs": ["6F9619FF-8B86-D011-B42D-00C04FC964F3"]}],
             "topics": [], "tombstones": []}}
            """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fileURL)

        let library = await store().load().library

        let saved = library.articles.values.filter(\.isSaved).sorted { $0.title < $1.title }
        #expect(saved.map(\.title) == ["First", "Saved before"])
        #expect(saved.map(\.savedAt) == [.hours(2), .hours(1)])
        #expect(library.articles.count == 3)
        #expect(library.stories.count == 2)
    }

    /// Files from before page texts have no such fields.
    @Test func articlesWithoutPageTextsAreSavedWithoutTheFields() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = sampleLibrary()

        await write(library, with: store())

        let json = try #require(String(data: Data(contentsOf: fileURL), encoding: .utf8))
        #expect(!json.contains("\"pageText\"") && !json.contains("pageSummary"))
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
        try Data("{\"version\": 99, \"library\": {}}".utf8).write(to: fileURL)

        let result = await store().load()

        #expect(result.problem == "The library was saved by a newer version of Feedini (schema 99).")
        #expect(try backups().count == 1)
    }

    /// Schema 3 derives feed and article IDs from addresses and keys; the files of page texts get the new IDs.
    @Test func givesTheFilesOfPageTextsTheNewIDsOfASchema2File() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        var library = sampleLibrary()
        let old = try #require(library.articles.keys.first)
        // Listed, but its file is gone: nothing to rename, and it is forgotten.
        let gone = Article.stub(feed: try #require(library.feeds.first).id)
        library.articles[gone.id] = gone
        library.pageTextIDs = [old, gone.id]
        let store = store()
        try await store.storePageText("The text of the page.", for: old)
        let json = try String(
            decoding: LibraryStore.encoder.encode(LibraryStore.File(version: 2, library: library)), as: UTF8.self)
        try Data(json.utf8).write(to: fileURL)

        let loaded = await store.load().library

        let id = try #require(loaded.articles.values.first { $0.key == library.articles[old]?.key }?.id)
        #expect(id != old)
        #expect(loaded.pageTextIDs == [id])
        #expect(await store.pageText(for: id) == "The text of the page.")
        #expect(await store.pageText(for: old) == nil)
        // Written at once with the new IDs.
        let saved = try #require(String(data: Data(contentsOf: fileURL), encoding: .utf8))
        #expect(saved.contains("\"version\" : 3"))
        #expect(await LibraryStore(fileURL: fileURL).load().library == loaded)
    }
}
