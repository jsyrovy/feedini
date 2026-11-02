import Foundation
import Testing

@testable import Feedini

struct FolderTests {
    private let tech = Feed.stub("Tech")
    private let news = Feed.stub("News")
    private let blog = Feed.stub("Blog")

    private var library: Library {
        Library(feeds: [tech, news, blog], articles: [])
    }

    @Test func addsFoldersAtTheEndWithCheckedNames() throws {
        var library = library

        let first = try library.addFolder(named: "  Daily  ")
        let second = try library.addFolder(named: "Work")

        #expect(library.folders.map(\.name) == ["Daily", "Work"])
        #expect(library.folders.map(\.id) == [first, second])
        #expect(throws: FolderNameError.empty) { try library.addFolder(named: " \n") }
        #expect(throws: FolderNameError.taken) { try library.addFolder(named: "daily") }
        #expect(library.folders.count == 2)
        #expect(FolderNameError.empty.message == "Enter a name.")
        #expect(FolderNameError.taken.message == "There is a folder with this name already.")
    }

    @Test func namesAreOneLineAndAtMostFortyCharacters() throws {
        var library = library
        let fits = String(repeating: "a", count: 40)

        try library.addFolder(named: " Daily\n\n  news\t ")
        try library.addFolder(named: fits)

        #expect(library.folders.map(\.name) == ["Daily news", fits])
        #expect(throws: FolderNameError.tooLong) { try library.addFolder(named: fits + "b") }
        #expect(throws: FolderNameError.tooLong) { try library.renameFolder(library.folders[0].id, to: fits + "b") }
        #expect(FolderNameError.tooLong.message == "Use at most 40 characters.")
    }

    @Test func shortensLongNamesWithAnEllipsis() {
        let long =
            "Po aktualizaci se mi zase zacaly zobrazovat\nissues ohledne dotazu " + String(repeating: "x", count: 500)

        let shortened = Folder.shortenedName(long)

        #expect(shortened == "Po aktualizaci se mi zase zacaly zobraz…")
        #expect(shortened.count == 40)
        // No space before the ellipsis.
        #expect(Folder.shortenedName("Twelve chars and more", to: 8) == "Twelve…")
        #expect(Folder.shortenedName("  Short  ") == "Short")
    }

    @Test func renamesAFolder() throws {
        var library = library
        let daily = try library.addFolder(named: "Daily")
        try library.addFolder(named: "Work")

        // Its own name in another case is fine.
        try library.renameFolder(daily, to: "DAILY")
        #expect(library.folder(daily)?.name == "DAILY")
        #expect(throws: FolderNameError.taken) { try library.renameFolder(daily, to: "work") }
        #expect(throws: FolderNameError.empty) { try library.renameFolder(daily, to: "") }
        #expect(library.folder(daily)?.name == "DAILY")
        try library.renameFolder(UUID(), to: "Nothing")
        #expect(library.folders.map(\.name) == ["DAILY", "Work"])
    }

    @Test func movesFeedsBetweenFolders() throws {
        var library = library
        let daily = try library.addFolder(named: "Daily")
        let work = try library.addFolder(named: "Work")

        library.moveFeeds([tech.id, news.id], to: daily)
        library.moveFeeds([news.id], to: work)
        library.moveFeeds([blog.id], to: UUID())

        #expect(library.folderIDsByFeed() == [tech.id: daily, news.id: work])
        #expect(library.feedsByTitle.map(\.title) == ["Blog", "News", "Tech"])

        library.moveFeeds([tech.id], to: nil)
        #expect(library.folderIDsByFeed() == [news.id: work])
    }

    @Test func removingAFolderKeepsItsFeeds() throws {
        var library = library
        let daily = try library.addFolder(named: "Daily")
        library.moveFeeds([tech.id], to: daily)

        library.removeFolder(daily)

        #expect(library.folders.isEmpty)
        #expect(library.feeds.count == 3)
        #expect(library.feed(tech.id)?.folderID == nil)
    }

    @Test func loadingDropsFoldersThatDontExist() throws {
        let daily = Folder(name: "Daily")
        let saved = Library(
            feeds: [.stub("Tech", folder: daily.id), .stub("News", folder: UUID())], articles: [], folders: [daily])

        let loaded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(saved))

        #expect(loaded.feeds.map(\.folderID) == [daily.id, nil])
    }

    @Test func loadingShortensNamesAndKeepsThemUnique() throws {
        let long = String(repeating: "a", count: 29_643)
        let saved = Library(
            feeds: [], articles: [],
            folders: [
                Folder(name: long), Folder(name: long + "b"), Folder(name: "Two\nlines"), Folder(name: " "),
                Folder(name: "folder"),
            ])

        let loaded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(saved))

        let shortened = String(repeating: "a", count: 39) + "…"
        #expect(
            loaded.folders.map(\.name) == [
                shortened, String(repeating: "a", count: 37) + "… 2", "Two lines", "Folder", "folder 2",
            ])
        #expect(loaded.folders.map(\.id) == saved.folders.map(\.id))
        #expect(loaded.folders.allSatisfy { $0.name.count <= Folder.maxNameLength })
    }

    @Test func knowsWhichSidebarItemsExist() throws {
        var library = library
        let daily = try library.addFolder(named: "Daily")
        let topic = Topic(name: "Apple", description: "")
        library.topics[topic.id] = topic

        for item in [SidebarSelection.all, .feed(tech.id), .folder(daily), .topic(topic.id)] {
            #expect(library.contains(item))
        }
        for item in [SidebarSelection.feed(UUID()), .folder(UUID()), .topic(UUID())] {
            #expect(!library.contains(item))
        }
    }

    @Test func findsOrAddsAFolderByName() throws {
        var library = library
        let daily = try library.addFolder(named: "Daily")

        #expect(library.folderID(named: " daily ") == daily)
        let added = library.folderID(named: "Work")
        let work = try #require(added)
        #expect(library.folder(work)?.name == "Work")
        #expect(library.folderID(named: "  ") == nil)
        // A long OPML category is shortened, and found again by the long name.
        let long = String(repeating: "Long ", count: 20)
        let addedLong = library.folderID(named: long)
        let shortened = try #require(addedLong)
        #expect(library.folder(shortened)?.name == "Long Long Long Long Long Long Long Long…")
        #expect(library.folderID(named: long) == shortened)
        #expect(library.folders.count == 3)
    }

    @Test func movesFoldersToTheTargetsPlace() throws {
        var library = library
        let ids = try ["A", "B", "C", "D"].map { try library.addFolder(named: $0) }
        let names = { library.folders.map(\.name).joined() }

        library.moveFolder(ids[0], to: ids[2])
        #expect(names() == "BCAD")
        library.moveFolder(ids[3], to: ids[1])
        #expect(names() == "DBCA")
        library.moveFolder(ids[1], by: -1)
        #expect(names() == "BDCA")
        library.moveFolder(ids[1], by: -1)
        #expect(names() == "BDCA")
        library.moveFolder(ids[3], by: 10)
        #expect(names() == "BCAD")
        library.moveFolder(UUID(), by: 1)
        library.moveFolder(ids[0], to: UUID())
        #expect(names() == "BCAD")
    }

    @Test func dragTextCarriesFeedsAndFolders() {
        let id = UUID()

        for item in [SidebarSelection.feed(id), .folder(id)] {
            #expect(SidebarDrag.text(for: item).flatMap(SidebarDrag.item(from:)) == item)
        }
        #expect(SidebarDrag.text(for: .all) == nil)
        #expect(SidebarDrag.text(for: .topic(id)) == nil)
        #expect(SidebarDrag.item(from: "feedini-feed:nonsense") == nil)
        #expect(SidebarDrag.item(from: "feedini-folder:") == nil)
        #expect(SidebarDrag.item(from: id.uuidString) == nil)
    }

    @Test func droppingAFeedPutsItWhereTheTargetIs() throws {
        var library = library
        let daily = try library.addFolder(named: "Daily")
        let work = try library.addFolder(named: "Work")
        library.moveFeeds([news.id], to: work)

        #expect(SidebarDrag.drop(.feed(tech.id), onto: .folder(daily), in: &library))
        #expect(library.feed(tech.id)?.folderID == daily)
        #expect(SidebarDrag.drop(.feed(tech.id), onto: .feed(news.id), in: &library))
        #expect(library.feed(tech.id)?.folderID == work)
        #expect(SidebarDrag.drop(.feed(tech.id), onto: .feed(blog.id), in: &library))
        #expect(library.feed(tech.id)?.folderID == nil)
        #expect(!SidebarDrag.drop(.feed(tech.id), onto: .feed(blog.id), in: &library))
        #expect(!SidebarDrag.drop(.feed(tech.id), onto: .all, in: &library))
        #expect(!SidebarDrag.drop(.feed(tech.id), onto: .folder(UUID()), in: &library))
    }

    @Test func droppingAFolderMovesIt() throws {
        var library = library
        let ids = try ["A", "B", "C"].map { try library.addFolder(named: $0) }
        library.moveFeeds([tech.id], to: ids[0])
        let names = { library.folders.map(\.name).joined() }

        #expect(SidebarDrag.drop(.folder(ids[0]), onto: .folder(ids[1]), in: &library))
        #expect(names() == "BAC")
        // Onto a feed in a folder: the place of that folder.
        #expect(SidebarDrag.drop(.folder(ids[2]), onto: .feed(tech.id), in: &library))
        #expect(names() == "BCA")
        // Onto a feed in no folder: the end.
        #expect(SidebarDrag.drop(.folder(ids[1]), onto: .feed(blog.id), in: &library))
        #expect(names() == "CAB")
        #expect(!SidebarDrag.drop(.folder(ids[1]), onto: .topic(UUID()), in: &library))
        #expect(!SidebarDrag.drop(.all, onto: .folder(ids[0]), in: &library))
    }
}
