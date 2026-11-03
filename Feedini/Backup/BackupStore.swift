import Foundation
import SystemConfiguration

/// The backup files in iCloud Drive: `Feedini/Backups/<Mac name>/<date>.feedinibackup`, a folder per Mac, so each
/// Mac thins out only its own backups. Works with file coordination (iCloud Drive syncs the files meanwhile). The
/// calls may wait – for macOS asking for access to iCloud Drive, for a download – so they run off the main actor.
struct BackupStore: Sendable {
    /// A backup file.
    struct Backup: Sendable, Hashable, Identifiable {
        var url: URL
        /// The Mac it was made on (its folder).
        var device: String
        var created: Date
        var kind: BackupFile.Kind
        var size: Int?
        /// `false` when iCloud Drive keeps the file only in the cloud; reading it downloads it.
        var isDownloaded: Bool

        var id: URL { url }
    }

    /// The iCloud Drive folder; there is none while iCloud Drive is off.
    let drive: URL
    /// The name of this Mac, the folder of its backups.
    let device: String
    private let timeZone: TimeZone

    init(drive: URL = BackupStore.iCloudDrive, device: String = BackupStore.computerName, timeZone: TimeZone = .current)
    {
        self.drive = drive
        self.device = Self.folderName(device)
        self.timeZone = timeZone
    }

    /// `~/Library/Mobile Documents/com~apple~CloudDocs`; the app isn't sandboxed, so it writes there like into any
    /// folder (no iCloud entitlements).
    static var iCloudDrive: URL {
        URL.libraryDirectory.appending(
            components: "Mobile Documents", "com~apple~CloudDocs", directoryHint: .isDirectory)
    }

    /// The computer name from System Settings → General → Sharing.
    static var computerName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }

    /// The folder of all backups (iCloud Drive → Feedini → Backups).
    var directory: URL {
        drive.appending(components: "Feedini", "Backups", directoryHint: .isDirectory)
    }

    private var ownDirectory: URL {
        directory.appending(path: device, directoryHint: .isDirectory)
    }

    /// A Mac name as a folder name: without slashes and colons, never empty or hidden.
    static func folderName(_ name: String) -> String {
        let cleaned = name.map { $0 == "/" || $0 == ":" ? "-" : $0 }
        let trimmed = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(".") else { return "Mac" }
        return trimmed
    }

    /// Writes a backup into this Mac's folder.
    @concurrent func write(_ data: Data, created: Date, kind: BackupFile.Kind) async throws(BackupError) -> Backup {
        try checkDrive()
        let url = ownDirectory.appending(path: BackupFile.name(created: created, kind: kind, timeZone: timeZone))
        do {
            try FileManager.default.createDirectory(at: ownDirectory, withIntermediateDirectories: true)
            try coordinate(.writing(.forReplacing), at: url) { try data.write(to: $0, options: .atomic) }
        } catch {
            throw Self.backupError(error)
        }
        return Backup(url: url, device: device, created: created, kind: kind, size: data.count, isDownloaded: true)
    }

    /// The backups of all Macs, newest first.
    @concurrent func backups() async throws(BackupError) -> [Backup] {
        try checkDrive()
        let devices: [URL]
        do {
            devices = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            throw Self.backupError(error)
        }
        var found: [Backup] = []
        for folder in devices where (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            found += try backups(in: folder)
        }
        return found.sorted { $0.created != $1.created ? $0.created > $1.created : $0.device < $1.device }
    }

    /// The backups made on this Mac, newest first; only its folder is read.
    @concurrent func ownBackups() async throws(BackupError) -> [Backup] {
        try checkDrive()
        return try backups(in: ownDirectory).sorted { $0.created > $1.created }
    }

    /// Reads a backup, downloading it first if iCloud Drive keeps it only in the cloud.
    @concurrent func read(_ backup: Backup) async throws(BackupError) -> Data {
        do {
            return try coordinate(.reading, at: backup.url) { try Data(contentsOf: $0) }
        } catch {
            throw Self.backupError(error)
        }
    }

    /// Deletes the backups; a failure is only logged (the next backup tries again).
    @concurrent func delete(_ backups: [Backup]) async {
        for backup in backups {
            do {
                try coordinate(.writing(.forDeleting), at: backup.url) { try FileManager.default.removeItem(at: $0) }
            } catch {
                Log.backup.error("Deleting a backup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func checkDrive() throws(BackupError) {
        do {
            guard try drive.checkResourceIsReachable() else { throw BackupError.iCloudDriveOff }
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            throw .iCloudDriveOff
        } catch {
            throw Self.backupError(error)
        }
    }

    private static func backupError(_ error: any Error) -> BackupError {
        if let error = error as? BackupError {
            return error
        }
        let nsError = error as NSError
        let posix = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap {
            $0.domain == NSPOSIXErrorDomain ? Int32($0.code) : nil
        }
        if [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue].contains(nsError.code)
            && nsError.domain == NSCocoaErrorDomain || posix == EPERM || posix == EACCES
        {
            return .noAccess
        }
        return .failed(error.localizedDescription)
    }

    /// The backups in a Mac's folder, none if it doesn't exist (yet).
    private func backups(in folder: URL) throws(BackupError) -> [Backup] {
        let keys: [URLResourceKey] = [.fileSizeKey, .ubiquitousItemDownloadingStatusKey]
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            throw Self.backupError(error)
        }
        return files.compactMap { file in
            let name = BackupFile.withoutPlaceholder(file.lastPathComponent)
            guard let (created, kind) = BackupFile.parse(name, timeZone: timeZone) else { return nil }
            let isPlaceholder = name != file.lastPathComponent
            let values = try? file.resourceValues(forKeys: Set(keys))
            let status = values?.ubiquitousItemDownloadingStatus
            return Backup(
                url: folder.appending(path: name), device: folder.lastPathComponent, created: created, kind: kind,
                size: isPlaceholder ? nil : values?.fileSize,
                isDownloaded: !isPlaceholder && (status == nil || status == .current || status == .downloaded))
        }
    }

    private enum Access {
        case reading
        case writing(NSFileCoordinator.WritingOptions)
    }

    /// Runs `body` with file coordination; an error of the coordination wins over one of `body`.
    private func coordinate<Result>(_ access: Access, at url: URL, _ body: (URL) throws -> Result) throws -> Result {
        var coordinationError: NSError?
        var result: Swift.Result<Result, any Error>?
        let accessor = { (url: URL) in result = Swift.Result { try body(url) } }
        switch access {
        case .reading:
            NSFileCoordinator().coordinate(
                readingItemAt: url, options: [], error: &coordinationError, byAccessor: accessor)
        case .writing(let options):
            NSFileCoordinator().coordinate(
                writingItemAt: url, options: options, error: &coordinationError, byAccessor: accessor)
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
