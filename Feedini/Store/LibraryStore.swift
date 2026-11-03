import Foundation

/// Loads and saves the library as one versioned JSON file, and the texts of source pages (P / T) as files of their own
/// next to it (`pages/<article id>.txt`).
///
/// Saving is debounced: the first change after a save starts a `debounce` countdown and the latest library is written
/// when it ends, so a burst of changes (reading with J/K) costs one write. Writes are atomic. `flush()` writes a
/// pending change right away (at quit).
///
/// A page text is written at once (`storePageText`) and read only when needed (`pageText(for:)`). The library lists
/// the stored ones (`Library.pageTextIDs`); a text it no longer lists is deleted once that library is written, and
/// loading deletes files it doesn't list (left by a crash) and forgets listed texts without a file.
actor LibraryStore {
    static let schemaVersion = 1

    struct LoadResult: Sendable {
        var library: Library
        /// Set when the file couldn't be used and was moved aside: a corrupt file, or one from a newer Feedini.
        var problem: String?
    }

    let fileURL: URL
    /// The directory of the page texts.
    nonisolated let pagesURL: URL
    private let debounce: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var pending: Library?
    private var saveTask: Task<Void, Never>?
    /// The page texts of the last library written or loaded, without those stored again since: a library that was
    /// waiting to be written when one of them was stored doesn't delete it.
    private var savedPageTextIDs: Set<Article.ID> = []

    init(
        fileURL: URL = LibraryStore.defaultFileURL, debounce: Duration = .seconds(2),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.fileURL = fileURL
        pagesURL = fileURL.deletingLastPathComponent().appending(path: "pages", directoryHint: .isDirectory)
        self.debounce = debounce
        self.sleep = sleep
    }

    /// `~/Library/Application Support/Feedini/library.json`.
    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(components: "Feedini", "library.json")
    }

    /// Reads the library; an empty one when there is no file yet. A file that can't be read is moved aside (never
    /// overwritten) and an empty library is returned with the reason.
    func load() -> LoadResult {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return LoadResult(library: Library())
        } catch {
            return moveAside(because: "The library couldn't be read: \(error.localizedDescription)")
        }
        do {
            let file = try Self.decoder.decode(File.self, from: data)
            var library = file.library
            let moved = movePageTexts(file.legacyPageTexts, into: &library)
            checkPageTexts(of: &library)
            if moved {
                // Written without the texts at once, so they aren't moved again at every start.
                pending = library
                writePending()
            }
            Log.store.info("Loaded \(library.articles.count) articles of \(library.feeds.count) feeds")
            return LoadResult(library: library)
        } catch let newer as File.NewerVersion {
            return moveAside(
                because: "The library was saved by a newer version of Feedini (schema \(newer.version)).")
        } catch {
            return moveAside(because: "The library file is damaged: \(error.localizedDescription)")
        }
    }

    /// Saves the library after the debounce delay; a later call before then replaces it.
    func save(_ library: Library) {
        pending = library
        guard saveTask == nil else { return }
        saveTask = Task { [debounce, sleep] in
            try? await sleep(debounce)
            self.writePending()
        }
    }

    /// Writes the text of an article's source page; it is kept once a written library lists it. Written off the store,
    /// so it doesn't wait for a library being written.
    @concurrent nonisolated func storePageText(_ text: String, for id: Article.ID) async throws {
        // Before the file: a library written meanwhile doesn't list it yet.
        await unconfirmPageText(id)
        try writePageText(text, for: id)
    }

    /// The stored text of an article's source page; `nil` when there is none. Read off the store (and the main actor),
    /// so it doesn't wait for a library being written.
    @concurrent nonisolated func pageText(for id: Article.ID) async -> String? {
        guard let data = try? Data(contentsOf: pageTextURL(id)) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Writes a pending change now.
    func flush() {
        saveTask?.cancel()
        writePending()
    }

    private func writePending() {
        saveTask = nil
        guard let library = pending else { return }
        pending = nil
        do {
            let data = try Self.encoder.encode(File(version: Self.schemaVersion, library: library))
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.store.error("Saving the library failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let kept = library.pageTextIDs
        // Usually the same set (unchanged storage), which compares at once.
        guard kept != savedPageTextIDs else { return }
        deletePageTexts(savedPageTextIDs.subtracting(kept))
        savedPageTextIDs = kept
    }

    // MARK: Page texts

    nonisolated func pageTextURL(_ id: Article.ID) -> URL {
        pagesURL.appending(path: "\(id.uuidString).txt", directoryHint: .notDirectory)
    }

    private nonisolated func writePageText(_ text: String, for id: Article.ID) throws {
        try FileManager.default.createDirectory(at: pagesURL, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: pageTextURL(id), options: .atomic)
    }

    private func unconfirmPageText(_ id: Article.ID) {
        savedPageTextIDs.remove(id)
    }

    /// Writes the texts a file from before page files had in its articles; returns whether there were any.
    private func movePageTexts(_ texts: [Article.ID: String], into library: inout Library) -> Bool {
        guard !texts.isEmpty else { return false }
        for (id, text) in texts where library.articles[id] != nil {
            do {
                try writePageText(text, for: id)
                library.pageTextIDs.insert(id)
            } catch {
                Log.store.error("Moving a page text out failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        let count = library.pageTextIDs.count
        Log.store.info("Moved \(count) page texts out of the library")
        return true
    }

    /// Keeps the listed texts that have a file and deletes the files of others.
    private func checkPageTexts(of library: inout Library) {
        let files = Set(
            ((try? FileManager.default.contentsOfDirectory(atPath: pagesURL.path)) ?? []).compactMap { name in
                name.hasSuffix(".txt") ? UUID(uuidString: String(name.dropLast(4))) : nil
            })
        let listed = library.pageTextIDs.filter { library.articles[$0] != nil }
        library.pageTextIDs = listed.intersection(files)
        deletePageTexts(files.subtracting(listed))
        savedPageTextIDs = library.pageTextIDs
    }

    private func deletePageTexts(_ ids: Set<Article.ID>) {
        for id in ids {
            do {
                try FileManager.default.removeItem(at: pageTextURL(id))
            } catch CocoaError.fileNoSuchFile {
            } catch {
                Log.store.error("Deleting a page text failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func moveAside(because problem: String) -> LoadResult {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backup)
            Log.store.error("\(problem, privacy: .public) Moved to \(backup.path, privacy: .public)")
        } catch {
            Log.store.error("\(problem, privacy: .public) Moving it aside failed: \(error.localizedDescription)")
        }
        return LoadResult(library: Library(), problem: problem)
    }

    /// The content of the library file, also inside a backup (`BackupFile`). Migrations of older schema versions go
    /// into its decoding, so restoring an old backup migrates it like loading does.
    struct File: Codable {
        struct NewerVersion: Error {
            var version: Int
        }

        /// The page text of an article in a file from before page files.
        private struct LegacyArticle: Decodable {
            var id: Article.ID
            var pageText: String?
        }

        private enum CodingKeys: String, CodingKey {
            case version, library
        }

        private enum LegacyKeys: String, CodingKey {
            case articles, pageTexts
        }

        var version: Int
        var library: Library
        /// The page texts in the articles of a file from before page files (one without `pageTexts`).
        var legacyPageTexts: [Article.ID: String] = [:]

        init(version: Int, library: Library) {
            self.version = version
            self.library = library
        }

        /// The version is checked before the library is decoded, so a newer file isn't decoded for nothing.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            guard version <= LibraryStore.schemaVersion else { throw NewerVersion(version: version) }
            library = try container.decode(Library.self, forKey: .library)
            let legacy = try container.nestedContainer(keyedBy: LegacyKeys.self, forKey: .library)
            if !legacy.contains(.pageTexts) {
                let articles = try legacy.decode([LegacyArticle].self, forKey: .articles)
                legacyPageTexts = Dictionary(
                    articles.compactMap { article in article.pageText.map { (article.id, $0) } },
                    uniquingKeysWith: { _, last in last })
            }
        }
    }

    /// How the library file is written and read (also used by tests).
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
