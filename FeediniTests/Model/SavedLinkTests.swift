import Foundation
import Testing

@testable import Feedini

struct SavedLinkTests {
    private let feed = Feed.stub("Tech")

    @Test func addressesBecomeHTTPS() throws {
        #expect(try SavedLink.url(from: " example.com/a ") == URL(string: "https://example.com/a"))
        #expect(try SavedLink.url(from: "http://example.com/a") == URL(string: "https://example.com/a"))
        #expect(try SavedLink.url(from: "https://example.com/a?b=1#c") == URL(string: "https://example.com/a?b=1#c"))
        for address in ["", "not an address", "ftp://example.com/a", "intranet/page"] {
            #expect(throws: SavedLink.Failure.invalidAddress) { try SavedLink.url(from: address) }
        }
        #expect(SavedLink.Failure.invalidAddress.message == "This isn't a web address.")
    }

    @Test func keysLeaveOutWhatDoesNotChangeThePage() {
        let key = { (address: String) in SavedLink.key(of: URL(string: address)!) }
        #expect(key("https://Example.COM/News/A/") == "example.com/News/A")
        #expect(key("http://example.com:80/news/a#comments") == "example.com/news/a")
        #expect(key("https://example.com:443/news/a") == "example.com/news/a")
        #expect(key("https://example.com:8443/news/a") == "example.com:8443/news/a")
        #expect(key("https://example.com/") == "example.com")
        #expect(
            key("https://example.com/a?id=7&utm_source=x&UTM_Medium=y&fbclid=z&gclid=1&page=2")
                == "example.com/a?id=7&page=2")
        #expect(key("https://example.com/a?utm_source=x") == "example.com/a")
        #expect(key("https://example.com/a%20b?q=a%26b") == "example.com/a%20b?q=a%26b")
    }

    @Test func siteAndPlaceholderTitleComeFromTheAddress() {
        let url = URL(string: "https://WWW.Example.com/news/a?id=1")!
        #expect(SavedLink.site(of: url) == "example.com")
        #expect(SavedLink.site(of: URL(string: "https://blog.example.com/a")!) == "blog.example.com")
        #expect(SavedLink.placeholderTitle(of: url) == "WWW.Example.com/news/a?id=1")
    }

    @Test func savingANewLinkAddsAnUnreadSavedArticleOfNoFeed() throws {
        var library = Library(feeds: [feed], articles: [])
        let url = URL(string: "https://www.example.com/essay?utm_source=share")!

        let outcome = library.saveLink(url, at: .hours(1))

        guard case .added(let id) = outcome else {
            Issue.record("Not added: \(outcome)")
            return
        }
        let article = try #require(library.articles[id])
        #expect(article.isSavedLink)
        #expect(article.feedID == SavedLink.feedID)
        #expect(article.key == "www.example.com/essay")
        #expect(article.link == url)
        #expect(article.title == "www.example.com/essay?utm_source=share")
        #expect(article.site == "example.com")
        #expect(article.firstSeen == .hours(1))
        #expect(article.savedAt == .hours(1))
        #expect(!article.isRead)
        #expect(library.sourceTitle(of: article) == "example.com")
        #expect(library.feeds == [feed])
    }

    @Test func savingALinkAgainChangesNothing() {
        var library = Library(feeds: [feed], articles: [])
        guard case .added(let id) = library.saveLink(URL(string: "https://example.com/a")!, at: .hours(1)) else {
            Issue.record("Not added")
            return
        }
        let before = library

        #expect(library.saveLink(URL(string: "http://EXAMPLE.com/a/#top")!, at: .hours(2)) == .alreadySaved(id))
        #expect(library == before)
    }

    @Test func savingALinkRemovedFromSavedSavesItAgain() {
        let link = Article(
            feedID: SavedLink.feedID, key: "example.com/a", title: "Essay",
            link: URL(string: "https://example.com/a?ref=feedini"), firstSeen: .hours(0), readAt: .hours(1))
        var library = Library(feeds: [], articles: [link])

        #expect(library.saveLink(URL(string: "https://example.com/a")!, at: .hours(2)) == .saved(link.id))
        #expect(library.articles[link.id]?.savedAt == .hours(2))
        #expect(library.articles.count == 1)
    }

    @Test func savingTheLinkOfAFeedArticleSavesThatArticle() {
        let article = Article.stub(feed: feed.id)
        var library = Library(feeds: [feed], articles: [article])
        let url = URL(string: article.link!.absoluteString + "?utm_campaign=rss")!

        #expect(library.saveLink(url, at: .hours(2)) == .saved(article.id))
        #expect(library.articles[article.id]?.savedAt == .hours(2))
        #expect(library.articles.count == 1)
        #expect(library.saveLink(url, at: .hours(3)) == .alreadySaved(article.id))
    }

    @Test func theArticleAtAnAddressPrefersSavedLinksThenSavedArticles() {
        let url = URL(string: "https://example.com/a")!
        let older = Article(feedID: feed.id, key: "1", title: "Older", link: url, firstSeen: .hours(0))
        let newer = Article(feedID: feed.id, key: "2", title: "Newer", link: url, firstSeen: .hours(1))
        let saved = Article(
            feedID: feed.id, key: "3", title: "Saved", link: url, firstSeen: .hours(2), savedAt: .hours(2))
        let link = Article(
            feedID: SavedLink.feedID, key: "example.com/a", title: "Link",
            link: URL(string: "https://example.com/redirected"), firstSeen: .hours(3))

        #expect(Library(feeds: [feed], articles: [newer, older]).article(at: url)?.id == older.id)
        #expect(Library(feeds: [feed], articles: [older, saved]).article(at: url)?.id == saved.id)
        #expect(Library(feeds: [feed], articles: [older, saved, link]).article(at: url)?.id == link.id)
        // A saved link is also found by its address after a redirect.
        #expect(
            Library(feeds: [feed], articles: [link]).article(at: URL(string: "https://example.com/redirected")!)?.id
                == link.id)
        #expect(Library(feeds: [feed], articles: [older]).article(at: URL(string: "https://example.com/b")!) == nil)
    }

    @Test func savedLinksAreInSavedOnlyAndCountNowhereElse() {
        let article = Article.stub(feed: feed.id)
        var library = Library(feeds: [feed], articles: [article])
        guard case .added(let id) = library.saveLink(URL(string: "https://example.com/essay")!, at: .hours(1)) else {
            Issue.record("Not added")
            return
        }
        let all = StoryList.allEntries(in: library, summaryLanguage: "en", singleArticles: .never)

        #expect(StoryList.entries(all, matching: .all, folders: [:]).map(\.id) == [.loose(article.id)])
        let counts = StoryList.unreadCounts(all, folders: [:])
        #expect(counts.all == 1)
        #expect(counts.feeds == [feed.id: 1])
        let index = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let saved = StoryList.savedEntries(in: library, storyIDs: [:]) { index[$0] }
        #expect(saved.map(\.id) == [.savedArticle(id)])
        #expect(saved.first?.isSavedLink == true)
        #expect(saved.first?.title == "example.com/essay")
    }
}
