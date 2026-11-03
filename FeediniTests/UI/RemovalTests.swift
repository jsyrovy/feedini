import Foundation
import Testing

@testable import Feedini

struct RemovalTests {
    private let folder = Folder(name: "Daily")
    private let empty = Folder(name: "Empty")

    private let tech: Feed
    private let news: Feed
    private let blog = Feed.stub("Blog")

    init() {
        tech = Feed.stub("Tech", folder: folder.id)
        news = Feed.stub("News", folder: folder.id)
    }

    private var library: Library {
        var library = Library(
            feeds: [tech, news, blog],
            articles: [
                Article.stub(feed: tech.id, savedAt: .hours(1)), Article.stub(feed: news.id, savedAt: .hours(1)),
                Article.stub(feed: news.id, savedAt: .hours(2)),
            ])
        library.folders = [folder, empty]
        return library
    }

    private func feeds(_ titles: String...) -> Removal {
        .feeds(Set(library.feeds.filter { titles.contains($0.title) }.map(\.id)))
    }

    @Test func removingFeedsNamesThemAndTheSavedArticlesThatStay() {
        let blog = feeds("Blog")
        #expect(blog.action == "Remove")
        #expect(blog.title(in: library) == "Remove “Blog”?")
        #expect(blog.message(in: library) == "Its articles are removed too.")

        let tech = feeds("Tech")
        #expect(
            tech.message(in: library) == "Its articles are removed too, except 1 saved article, which stays in Saved.")

        let all = feeds("Tech", "News", "Blog")
        #expect(all.title(in: library) == "Remove 3 feeds?")
        #expect(
            all.message(in: library) == "Their articles are removed too, except 3 saved articles, which stay in Saved.")
        #expect(feeds("Blog", "News").message(in: library).hasPrefix("Their articles are removed too, except 2 "))
    }

    @Test func deletingAFolderSaysItsFeedsStay() {
        let daily = Removal.folder(folder.id)
        #expect(daily.action == "Delete")
        #expect(daily.title(in: library) == "Delete the folder “Daily”?")
        #expect(daily.message(in: library) == "Its 2 feeds stay, in no folder.")
        #expect(Removal.folder(empty.id).message(in: library) == "It has no feeds.")

        var library = library
        library.feeds[1].folderID = nil
        #expect(daily.message(in: library) == "Its feed stays, in no folder.")
    }
}
