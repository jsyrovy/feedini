import SafariServices
import SwiftUI

/// An opened row: a story with several articles (its summary and articles) or an article. Opening it reads it.
struct EntryDetailScreen: View {
    @Environment(ReadingSession.self) private var session
    let row: ListRow

    var body: some View {
        Group {
            if let entry = session.entry(row.entryID) {
                if case .story = row, entry.isMultiArticle {
                    StoryDetail(entry: entry)
                } else if let article = entry.singleArticle(at: row) {
                    ArticleDetail(article: article, entry: entry, row: row)
                }
            } else {
                ContentUnavailableView("Gone", systemImage: "tray", description: Text("This item isn't here anymore."))
            }
        }
        .onAppear { session.visit(row) }
    }
}

/// A story with several articles: its title, sources, summary and its articles.
private struct StoryDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(ReadingSession.self) private var session
    let entry: StoryEntry

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.title)
                        .font(.title2.bold())
                    Text(entry.sourceArticles.compactMap(model.library.sourceTitle(of:)).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let summary = entry.summary {
                        SummaryText(text: summary.text)
                    } else if entry.needsSummary {
                        Text("Feedini on the Mac writes a summary of this story.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("\(entry.articles.count) Articles") {
                ForEach(entry.articles) { article in
                    NavigationLink(value: Route.entry(.article(entry.id, article.id))) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(article.title)
                                .font(.body.weight(article.isRead ? .regular : .semibold))
                            Text(
                                [model.library.sourceTitle(of: article), RelativeTime.short(article.date, now: .now)]
                                    .compactMap { $0 }.joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button(entry.isRead ? "Mark as Unread" : "Mark as Read", systemImage: "circle") {
                    session.toggleRead(.story(entry.id))
                }
            }
        }
    }
}

/// An article: title, source, the TL;DR of its page or the summary of its story, the text from the feed, and the
/// source page in Feedini (Safari) or the browser.
private struct ArticleDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(ReadingSession.self) private var session
    @Environment(\.openURL) private var openURL
    let article: Article
    let entry: StoryEntry
    let row: ListRow
    @State private var page: URL?
    @State private var pageText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(article.title)
                    .font(.title2.bold())
                    .textSelection(.enabled)
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if article.isSavedLink {
                    Label(
                        "Saved link, added \(article.firstSeen.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "link"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                if let summary = article.pageSummary {
                    SummaryBox(title: "Page Summary") {
                        Text(summary.tldr)
                        if !summary.details.isEmpty {
                            SummaryText(text: summary.details.map { "- \($0)" }.joined(separator: "\n"))
                        }
                    }
                } else if entry.needsSummary, let summary = entry.summary {
                    SummaryBox(title: "Summary") {
                        SummaryText(text: summary.text)
                    }
                }
                Divider()
                if article.isSavedLink {
                    if let pageText {
                        Paragraphs(text: pageText)
                    } else {
                        Text("The text of the page isn't loaded.").foregroundStyle(.secondary)
                    }
                } else {
                    Paragraphs(text: article.text.isEmpty ? "No text in the feed." : article.text)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button(
                    article.isRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: article.isRead ? "circle" : "checkmark.circle"
                ) {
                    session.toggleRead(row)
                }
                Spacer()
                Button(article.isSaved ? "Unsave" : "Save", systemImage: article.isSaved ? "bookmark.fill" : "bookmark")
                {
                    session.toggleSaved(row)
                }
                Spacer()
                if let link = article.link {
                    Button("Open Page", systemImage: "safari") { open(link) }
                }
            }
        }
        .sheet(item: $page) { url in
            SafariView(url: url).ignoresSafeArea()
        }
        .task(id: article.id) {
            if article.isSavedLink {
                pageText = await model.pageText(article.id)
            }
        }
    }

    private var meta: String {
        let date = article.published.map { $0.formatted(date: .abbreviated, time: .shortened) }
        return [model.library.sourceTitle(of: article), article.author, date].compactMap { $0 }.joined(separator: " · ")
    }

    private func open(_ url: URL) {
        if model.preferences.pageOpening == .window {
            page = url
        } else {
            openURL(url)
        }
    }
}

/// A box above the text with an AI summary.
private struct SummaryBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// A web page in Safari's view inside the app (the user's Safari logins and cookies don't apply).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
