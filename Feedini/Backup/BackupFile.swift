import Foundation

/// Why backing up or restoring failed, with a message for the user.
enum BackupError: Error, Equatable {
    /// There is no iCloud Drive folder.
    case iCloudDriveOff
    /// macOS denied access to iCloud Drive.
    case noAccess
    /// Not a Feedini backup, or a damaged one.
    case notABackup
    /// Written by a newer Feedini.
    case newerVersion
    case failed(String)

    var message: String {
        switch self {
        case .iCloudDriveOff: "iCloud Drive is off (System Settings → Apple Account → iCloud)."
        case .noAccess: "Feedini has no access to iCloud Drive."
        case .notABackup: "The file isn't a Feedini backup, or it is damaged."
        case .newerVersion: "The backup was made by a newer version of Feedini."
        case .failed(let message): message
        }
    }
}

/// A backup file (pure): the library and the settings in one zlib-compressed JSON object – `format`, `version` (of
/// this format), `created`, `device`, `app`, `settings` and `library`, the same object as `library.json` with its own
/// schema version, so restoring reads it like loading does. Page texts aren't in it: they are big, may show what the
/// site knows about the user, and P / T load them again.
enum BackupFile {
    static let format = "feedini-backup"
    static let version = 1
    static let pathExtension = "feedinibackup"

    /// Backups made before a restore are told apart by their names.
    enum Kind: Equatable, Sendable {
        case regular, beforeRestore
    }

    struct Contents: Sendable, Equatable {
        var created: Date
        /// The name of the Mac it was made on.
        var device: String
        var appVersion: String
        var settings: BackedUpSettings
        var library: Library

        /// "42 feeds, 3,210 articles, 12 saved", for the confirmation of a restore.
        var summary: String {
            let saved =
                library.articles.values.count(where: \.isSaved)
                + library.stories.values.count {
                    $0.savedAt != nil
                }
            let counts = [counted(library.feeds.count, "feed"), counted(library.articles.count, "article")]
            return (saved == 0 ? counts : counts + ["\(saved.formatted()) saved"]).joined(separator: ", ")
        }

        private func counted(_ count: Int, _ noun: String) -> String {
            "\(count.formatted()) \(noun)\(count == 1 ? "" : "s")"
        }
    }

    // MARK: Names

    /// "2026-11-03_14-30-15.feedinibackup", "2026-11-03_14-30-15_before-restore.feedinibackup"; local time, without
    /// colons (Finder doesn't allow them) or spaces (easier in a shell).
    static func name(created: Date, kind: Kind, timeZone: TimeZone = .current) -> String {
        let stamp = formatter(timeZone).string(from: created)
        let suffix = kind == .beforeRestore ? beforeRestoreSuffix : ""
        return "\(stamp)\(suffix).\(pathExtension)"
    }

    /// The name of the file a placeholder stands for: iCloud Drive used to leave ".name.icloud" for a file it kept
    /// only in the cloud.
    static func withoutPlaceholder(_ name: String) -> String {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return name }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    /// The date and kind of a backup from its name (`withoutPlaceholder`); `nil` for other files.
    static func parse(_ name: String, timeZone: TimeZone = .current) -> (created: Date, kind: Kind)? {
        guard name.hasSuffix(".\(pathExtension)") else { return nil }
        var stem = String(name.dropLast(pathExtension.count + 1))
        var kind = Kind.regular
        if stem.hasSuffix(beforeRestoreSuffix) {
            stem = String(stem.dropLast(beforeRestoreSuffix.count))
            kind = .beforeRestore
        }
        return formatter(timeZone).date(from: stem).map { ($0, kind) }
    }

    private static let beforeRestoreSuffix = "_before-restore"

    private static func formatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }

    // MARK: Contents

    /// The compressed file. The page texts the library lists stay out (they are files of the store).
    static func encode(_ contents: Contents) throws(BackupError) -> Data {
        var library = contents.library
        library.pageTextIDs = []
        let file = Envelope(
            format: format, version: version, created: contents.created, device: contents.device,
            app: contents.appVersion, settings: contents.settings,
            library: LibraryStore.File(version: LibraryStore.schemaVersion, library: library))
        do {
            return try (encoder.encode(file) as NSData).compressed(using: .zlib) as Data
        } catch {
            throw .failed("The backup couldn't be written: \(error.localizedDescription)")
        }
    }

    static func decode(_ data: Data) throws(BackupError) -> Contents {
        let json: Data
        do {
            json = try (data as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw .notABackup
        }
        let file: Envelope
        do {
            file = try decoder.decode(Envelope.self, from: json)
        } catch is Envelope.NewerVersion, is LibraryStore.File.NewerVersion {
            throw .newerVersion
        } catch {
            throw .notABackup
        }
        return Contents(
            created: file.created, device: file.device, appVersion: file.app, settings: file.settings,
            library: file.library.library)
    }

    fileprivate struct Envelope: Codable {
        struct NewerVersion: Error {}

        private enum CodingKeys: String, CodingKey {
            case format, version, created, device, app, settings, library
        }

        var format: String
        var version: Int
        var created: Date
        var device: String
        var app: String
        var settings: BackedUpSettings
        var library: LibraryStore.File
    }

    /// The library file's, without the indentation (the file is compressed and not meant to be read as it is).
    private static var encoder: JSONEncoder {
        let encoder = LibraryStore.encoder
        encoder.outputFormatting.remove(.prettyPrinted)
        return encoder
    }

    private static var decoder: JSONDecoder { LibraryStore.decoder }
}

// In an extension, so the memberwise initializer stays.
extension BackupFile.Envelope {
    /// The format and version are checked before the rest is decoded.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        guard format == BackupFile.format else {
            throw DecodingError.dataCorruptedError(forKey: .format, in: container, debugDescription: "Not a backup")
        }
        version = try container.decode(Int.self, forKey: .version)
        guard version <= BackupFile.version else { throw NewerVersion() }
        created = try container.decode(Date.self, forKey: .created)
        device = try container.decode(String.self, forKey: .device)
        app = try container.decode(String.self, forKey: .app)
        settings = try container.decode(BackedUpSettings.self, forKey: .settings)
        library = try container.decode(LibraryStore.File.self, forKey: .library)
    }
}
