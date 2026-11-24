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
    /// The text of the source page instead of the feed text (P on the Mac).
    @State private var showsPageText = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(article.title)
                    .font(.title2.bold())
                    .textSelection(.enabled)
                Text(model.library.byline(of: article))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if article.isSavedLink {
                    SavedLinkLabel(article: article)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let summary = article.pageSummary {
                    SummaryBox(title: "Page Summary") {
                        PageSummaryText(summary: summary)
                    }
                } else if entry.needsSummary, let summary = entry.summary {
                    SummaryBox(title: "Summary") {
                        SummaryText(text: summary.text)
                    }
                }
                Divider()
                if article.isSavedLink || showsPageText {
                    PageTextSection(article: article, isStored: model.library.pageTextIDs.contains(article.id))
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
                if article.link != nil {
                    Spacer()
                    if article.isSavedLink {
                        Button("Reload Page", systemImage: "arrow.clockwise") { model.reloadPage(article.id) }
                            .disabled(model.pageStatus[article.id]?.isRunning == true)
                    } else {
                        Toggle("Page Text", systemImage: "doc.plaintext", isOn: $showsPageText)
                    }
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
        .onChange(of: showsPageText) { _, shows in
            if shows {
                model.loadPage(article.id)
            }
        }
    }

    private func open(_ url: URL) {
        if model.preferences.pageOpening == .window {
            page = url
        } else {
            openURL(url)
        }
    }
}

/// The text of the source page – loaded on request, then stored – or how loading it goes. A saved link has only
/// this text.
private struct PageTextSection: View {
    @Environment(AppModel.self) private var model
    let article: Article
    /// Passed in, so the text isn't read again on every change of the library.
    let isStored: Bool
    @State private var text: String?

    var body: some View {
        let work = model.pageStatus[article.id]
        VStack(alignment: .leading, spacing: 14) {
            if let work, work.isRunning || !isStored {
                PageLoadStatus(phase: work.phase)
            }
            if isStored, let text {
                if !article.isSavedLink {
                    Label("Text of the source page", systemImage: "doc.plaintext")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                PageTextBody(text: text, cutNote: "The text is cut off here. Open the page for the rest.")
            } else if !isStored && work == nil {
                Text(article.isSavedLink ? "The text of the page isn't loaded." : "Loading page…")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: [isStored, work?.isRunning == true]) {
            if isStored && work?.isRunning != true {
                text = await model.pageText(article.id)
            }
        }
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
