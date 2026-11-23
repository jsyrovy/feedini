import Foundation

/// A folder of feeds, made by the user (unlike topics, which the AI makes). One level: a folder holds feeds only, and
/// a feed is in at most one folder.
struct Folder: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    /// The longest name. The sidebar shows about 30 characters; menus and pickers grow with the name.
    static let maxNameLength = 40

    /// The name with every run of whitespace (line breaks too) made one space, trimmed.
    static func normalizedName(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The normalized name, cut to `length` characters ending in "…" when longer (OPML import, older files).
    static func shortenedName(_ name: String, to length: Int = maxNameLength) -> String {
        let name = normalizedName(name)
        guard name.count > length else { return name }
        return name.prefix(length - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Why a folder name can't be used.
enum FolderNameError: Error, Equatable, Sendable {
    case empty
    case tooLong
    case taken

    var message: String {
        switch self {
        case .empty: "Enter a name."
        case .tooLong: "Use at most \(Folder.maxNameLength) characters."
        case .taken: "There is a folder with this name already."
        }
    }
}

extension Library {
    func folder(_ id: Folder.ID) -> Folder? {
        folders.first { $0.id == id }
    }

    /// The folder of every feed in one. A feed's `folderID` is `nil` or an existing folder: removing a folder clears
    /// it, moving checks it and loading drops unknown ones.
    func folderIDsByFeed() -> [Feed.ID: Folder.ID] {
        Dictionary(uniqueKeysWithValues: feeds.compactMap { feed in feed.folderID.map { (feed.id, $0) } })
    }

    /// The feeds sorted by title, as the sidebar and Settings show them.
    var feedsByTitle: [Feed] {
        feeds.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The name normalized (`Folder.normalizedName`); it must not be empty, longer than `Folder.maxNameLength` or
    /// used by another folder (ignoring case).
    private func folderName(_ name: String, renaming id: Folder.ID? = nil) throws(FolderNameError) -> String {
        let name = Folder.normalizedName(name)
        guard !name.isEmpty else { throw .empty }
        guard name.count <= Folder.maxNameLength else { throw .tooLong }
        guard folder(named: name).map({ $0.id == id }) ?? true else { throw .taken }
        return name
    }

    private func folder(named name: String) -> Folder? {
        folders.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Adds a folder at the end.
    @discardableResult
    mutating func addFolder(named name: String) throws(FolderNameError) -> Folder.ID {
        let folder = Folder(name: try folderName(name))
        folders.append(folder)
        return folder.id
    }

    /// The folder with the name (ignoring case), added when there is none; `nil` for an empty name (OPML import). A
    /// long name is shortened (`Folder.shortenedName`), not refused, so that the feed isn't lost.
    mutating func folderID(named name: String) -> Folder.ID? {
        let name = Folder.shortenedName(name)
        return folder(named: name)?.id ?? (try? addFolder(named: name))
    }

    mutating func renameFolder(_ id: Folder.ID, to name: String) throws(FolderNameError) {
        let name = try folderName(name, renaming: id)
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].name = name
        }
    }

    /// Removes the folder; its feeds stay, in no folder.
    mutating func removeFolder(_ id: Folder.ID) {
        folders.removeAll { $0.id == id }
        for index in feeds.indices where feeds[index].folderID == id {
            feeds[index].folderID = nil
        }
    }

    /// Moves the feeds into the folder, or out of any for `nil`. An unknown folder changes nothing.
    mutating func moveFeeds(_ ids: some Sequence<Feed.ID>, to folder: Folder.ID?) {
        guard folder.map({ self.folder($0) != nil }) ?? true else { return }
        let ids = Set(ids)
        for index in feeds.indices where ids.contains(feeds[index].id) {
            feeds[index].folderID = folder
        }
    }

    /// Moves the folder to the place of the target: after it when moving down, before it when moving up.
    mutating func moveFolder(_ id: Folder.ID, to target: Folder.ID) {
        guard let from = folders.firstIndex(where: { $0.id == id }),
            let to = folders.firstIndex(where: { $0.id == target })
        else { return }
        folders.insert(folders.remove(at: from), at: to)
    }

    /// Moves the folder by `offset` places (negative: up), at most to the first or the last place.
    mutating func moveFolder(_ id: Folder.ID, by offset: Int) {
        guard let from = folders.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(from + offset, 0), folders.count - 1)
        moveFolder(id, to: folders[to].id)
    }

    /// Repairs the folders of a loaded file (edited by hand, or saved before names had a limit): names are normalized
    /// and shortened, numbered when that makes them clash ("Name 2"), and feeds in folders that don't exist are in
    /// none.
    mutating func repairFolders() {
        var names: [String] = []
        for index in folders.indices {
            let shortened = Folder.shortenedName(folders[index].name)
            let name = Self.uniqueName(shortened.isEmpty ? "Folder" : shortened, among: names)
            folders[index].name = name
            names.append(name)
        }
        let known = Set(folders.map(\.id))
        for index in feeds.indices where feeds[index].folderID.map({ !known.contains($0) }) == true {
            feeds[index].folderID = nil
        }
    }

    /// The name, or with the lowest number from 2 that isn't among the names (ignoring case), within the length.
    private static func uniqueName(_ name: String, among names: [String]) -> String {
        let isTaken = { (candidate: String) in names.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame } }
        guard isTaken(name) else { return name }
        var number = 2
        while true {
            let suffix = " \(number)"
            let candidate = Folder.shortenedName(name, to: Folder.maxNameLength - suffix.count) + suffix
            if !isTaken(candidate) {
                return candidate
            }
            number += 1
        }
    }
}

/// Dragging feeds and folders in the sidebar (pure). A dragged item is carried as text (`text(for:)`).
enum SidebarDrag {
    private static let feedPrefix = "feedini-feed:"
    private static let folderPrefix = "feedini-folder:"

    /// The text that carries a dragged feed or folder; `nil` for items that can't be dragged.
    static func text(for item: SidebarSelection) -> String? {
        switch item {
        case .feed(let id): feedPrefix + id.uuidString
        case .folder(let id): folderPrefix + id.uuidString
        case .all, .saved, .topic: nil
        }
    }

    /// The feed or folder a dropped text carries; `nil` for any other text.
    static func item(from text: String) -> SidebarSelection? {
        if text.hasPrefix(feedPrefix), let id = UUID(uuidString: String(text.dropFirst(feedPrefix.count))) {
            return .feed(id)
        }
        if text.hasPrefix(folderPrefix), let id = UUID(uuidString: String(text.dropFirst(folderPrefix.count))) {
            return .folder(id)
        }
        return nil
    }

    /// Drops an item onto another one, which puts it where the target is: a feed into the target folder (or the
    /// folder of the target feed, or out of any folder); a folder to the place of the target folder (or of the
    /// target feed's folder, or to the end for a feed in no folder). Returns whether it did anything.
    @discardableResult
    static func drop(_ item: SidebarSelection, onto target: SidebarSelection, in library: inout Library) -> Bool {
        let before = library
        let targetFolder: Folder.ID? =
            switch target {
            case .folder(let id): id
            case .feed(let id): library.feed(id)?.folderID
            case .all, .saved, .topic: nil
            }
        switch (item, target) {
        case (.feed(let id), .folder), (.feed(let id), .feed):
            library.moveFeeds([id], to: targetFolder)
        case (.folder(let id), .folder), (.folder(let id), .feed):
            // A feed in no folder is below all folders.
            if let target = targetFolder ?? library.folders.last?.id {
                library.moveFolder(id, to: target)
            }
        default:
            break
        }
        return library != before
    }
}
