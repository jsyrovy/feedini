#if DEBUG
    import SwiftUI

    /// The Debug menu, in Debug builds only: run the AI again over the saved data and add made-up articles.
    struct DebugCommands: Commands {
        let model: AppModel

        var body: some Commands {
            CommandMenu("Debug") {
                Button("Reorganize All (Cold Start)") { model.debugReorganize() }
                Button("Rewrite Summaries") { model.debugRewriteSummaries() }
                Divider()
                Button("Add Fake Articles") { model.debugAddFakeArticles() }
            }
        }
    }

    extension AppModel {
        /// Forgets all stories and topics; the AI organizes every article again, as on a first start.
        func debugReorganize() {
            update { library in
                library.stories = [:]
                library.topics = [:]
            }
            organize(retryingFailed: true)
        }

        /// Forgets all summaries; they are written again.
        func debugRewriteSummaries() {
            update { library in
                for id in library.stories.keys {
                    library.stories[id]?.summary = nil
                }
            }
            organize(retryingFailed: true)
        }

        /// Adds made-up articles about a few events to a "Debug" feed (its refreshes fail, it has no real URL).
        func debugAddFakeArticles() {
            update { library in
                let feed =
                    library.feeds.first { $0.url == DebugArticles.feedURL }
                    ?? Feed(title: "Debug", url: DebugArticles.feedURL, language: "en")
                if library.feed(feed.id) == nil {
                    library.feeds.append(feed)
                }
                for article in DebugArticles.make(feed: feed.id, now: .now) {
                    library.articles[article.id] = article
                }
            }
            organize()
        }
    }

    /// Made-up articles: a few about the same events, so the AI has something to group, and some in Czech.
    enum DebugArticles {
        static let feedURL = URL(string: "https://debug.feedini.invalid/feed.xml")!

        private static let samples: [(title: String, text: String, language: String)] = [
            (
                "Example Corp unveils a foldable laptop",
                "Example Corp showed a laptop whose screen folds in half. It ships in December.", "en"
            ),
            (
                "Hands-on: Example Corp's foldable laptop",
                "We tried the foldable laptop for an hour. The hinge feels solid, the crease is visible.", "en"
            ),
            (
                "Example Corp's foldable laptop costs $2,999",
                "The price of the new foldable laptop starts at $2,999 for 512 GB of storage.", "en"
            ),
            (
                "Skládací notebook od Example Corp stojí 70 tisíc korun",
                "Nový skládací notebook se v Česku začne prodávat v prosinci za 69 990 Kč.", "cs"
            ),
            (
                "City opens a new tram line", "The new tram line connects the station with the airport.", "en"
            ),
            (
                "Researchers find water ice on a distant moon",
                "A probe detected water ice under the surface of a moon of a gas giant.", "en"
            ),
            (
                "Nová verze editoru přidává podporu pro AI",
                "Oblíbený textový editor ve verzi 5.0 umí doplňovat kód pomocí jazykového modelu.", "cs"
            ),
        ]

        static func make(feed: Feed.ID, now: Date) -> [Article] {
            let run = UUID().uuidString.prefix(8)
            return samples.enumerated().map { index, sample in
                Article(
                    feedID: feed, key: "debug-\(run)-\(index)", title: sample.title,
                    link: URL(string: "https://debug.feedini.invalid/\(run)/\(index)"),
                    published: now.addingTimeInterval(-Double(index) * 600), author: "Debug", text: sample.text,
                    language: sample.language, firstSeen: now)
            }
        }
    }
#endif
