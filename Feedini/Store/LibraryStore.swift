import Foundation

/// Loads and saves the library as one versioned JSON file.
///
/// Saving is debounced: the first change after a save starts a `debounce` countdown and the latest library is written
/// when it ends, so a burst of changes (reading with J/K) costs one write. Writes are atomic. `flush()` writes a
/// pending change right away (at quit).
actor LibraryStore {
    static let schemaVersion = 1

    struct LoadResult: Sendable {
        var library: Library
        /// Set when the file couldn't be used and was moved aside: a corrupt file, or one from a newer Feedini.
        var problem: String?
    }

    let fileURL: URL
    private let debounce: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var pending: Library?
    private var saveTask: Task<Void, Never>?

    init(
        fileURL: URL = LibraryStore.defaultFileURL, debounce: Duration = .seconds(2),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.fileURL = fileURL
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
            let version = try JSONDecoder().decode(VersionProbe.self, from: data).version
            guard version <= Self.schemaVersion else {
                return moveAside(because: "The library was saved by a newer version of Feedini (schema \(version)).")
            }
            let file = try Self.decoder.decode(File.self, from: data)
            Log.store.info("Loaded \(file.library.articles.count) articles of \(file.library.feeds.count) feeds")
            return LoadResult(library: file.library)
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

    private struct File: Codable {
        var version: Int
        var library: Library
    }

    private struct VersionProbe: Decodable {
        var version: Int
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
