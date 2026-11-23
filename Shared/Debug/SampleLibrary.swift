#if DEBUG
    import Foundation

    /// A made-up library for looking at the app without real feeds (the `-sampleLibrary` launch argument of the
    /// iOS app): a story with a summary from two feeds in a topic, a story with a single article, loose articles, a
    /// read and a saved one, a folder. Debug builds only.
    enum SampleLibrary {
        static let argument = "-sampleLibrary"

        static func make(now: Date) -> Library {
            func url(_ path: String) -> URL { URL(string: "https://sample.feedini.invalid/\(path)")! }
            let tech = Feed(title: "Example Tech Daily", url: url("tech.xml"), language: "en")
            let news = Feed(title: "Sample News", url: url("news.xml"), language: "en")
            let science = Feed(title: "Science Notes", url: url("science.xml"), language: "en")
            func article(_ feed: Feed, _ title: String, _ text: String, hours: Double) -> Article {
                let date = now.addingTimeInterval(-hours * 3600)
                return Article(
                    feedID: feed.id, key: title, title: title, link: url(String(title.prefix(12))), published: date,
                    author: nil, text: text, language: "en", firstSeen: date)
            }
            let launch = article(
                tech, "Example Corp unveils a foldable laptop",
                "Example Corp showed a laptop whose screen folds in half. It ships in December.", hours: 1)
            let price = article(
                news, "The foldable laptop costs $2,999",
                "The price of the new foldable laptop starts at $2,999 for 512 GB of storage.", hours: 2)
            let tram = article(
                news, "City opens a new tram line", "The new tram line connects the station with the airport.",
                hours: 3)
            let ice = article(
                science, "Researchers find water ice on a distant moon",
                "A probe detected water ice under the surface of a moon of a gas giant.", hours: 5)
            var saved = article(
                tech, "A long read about keyboards", "Why mechanical keyboards came back, in five parts.", hours: 30)
            saved.readAt = now
            saved.savedAt = now
            var read = article(science, "An article read already", "Nothing new here.", hours: 6)
            read.readAt = now
            let gadgets = Topic(name: "Gadgets", description: "New devices and their prices", language: "en")
            let laptop = Story(
                title: "Example Corp's foldable laptop", topicID: gadgets.id, articleIDs: [launch.id, price.id],
                summary: Summary(
                    title: "Example Corp's foldable laptop ships in December for $2,999",
                    text: "Example Corp showed a laptop that folds in half. It costs $2,999 and ships in December.",
                    language: "en", articleIDs: [launch.id, price.id]))
            let city = Story(title: "City opens a new tram line", articleIDs: [tram.id])
            var library = Library()
            library.feeds = [tech, news, science]
            for article in [launch, price, tram, ice, saved, read] {
                library.articles[article.id] = article
            }
            library.stories = [laptop.id: laptop, city.id: city]
            library.topics = [gadgets.id: gadgets]
            if let folder = try? library.addFolder(named: "Reading") {
                library.moveFeeds([tech.id, science.id], to: folder)
            }
            return library
        }
    }
#endif
