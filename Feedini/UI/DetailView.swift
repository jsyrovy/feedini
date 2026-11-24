import SwiftUI

/// The detail of the row under the cursor: a story with several articles, an article's feed text, or its source page.
struct DetailView: View {
    @Environment(Reader.self) private var reader

    var body: some View {
        if let cursor = reader.cursor, let entry = reader.entry(cursor.entryID) {
            if let article = reader.cursorArticle {
                if reader.pageArticle == article.id, let link = article.link {
                    SourcePage(article: article, url: link)
                } else {
                    // A story of one article in another language shows the AI's translated gist above its text.
                    ArticleDetail(article: article, story: entry.isMultiArticle ? nil : entry)
                }
            } else {
                StoryDetail(entry: entry)
            }
        } else {
            ContentUnavailableView(
                "No Selection", systemImage: "doc.text", description: Text("Press ? for keyboard shortcuts."))
        }
    }
}

/// A story with several articles: its title and the list of its articles.
struct StoryDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader
    let entry: StoryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.title)
                    .font(.title.bold())
                    .textSelection(.enabled)
                Text("\(entry.feedIDs.count) sources · \(entry.articles.count) articles")
                    .foregroundStyle(.secondary)
                SummaryView(entry: entry)
                Divider()
                Text("Articles").font(.headline)
                ForEach(entry.articles) { article in
                    Button {
                        reader.visit(.article(entry.id, article.id))
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            UnreadDot(isUnread: !article.isRead)
                            if article.isSaved {
                                SavedMark().font(.caption)
                            }
                            if let source = model.library.sourceTitle(of: article) {
                                SourceLabel(title: source).font(.caption)
                            }
                            Text(article.title)
                                .foregroundStyle(article.isRead ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// An article with the text from its feed, or a saved link with the text of its page.
struct ArticleDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader
    let article: Article
    /// The one-article story the article is shown for, if any (for its summary).
    var story: StoryEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(article.title)
                    .font(.title.bold())
                    .textSelection(.enabled)
                Text(model.library.byline(of: article))
                    .foregroundStyle(.secondary)
                if article.isSavedLink {
                    SavedLinkLabel(article: article)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if let link = article.link {
                        OpenButtons(url: link)
                        PageButtons(article: article)
                    }
                    SaveButton(article: article)
                }
                // The page summary replaces the AI gist of the feed text: it is more complete.
                if PageSummaryView.isShown(for: article, status: model.pageStatus) {
                    PageSummaryView(article: article)
                } else if let story, story.needsSummary {
                    SummaryView(entry: story)
                }
                Divider()
                if article.isSavedLink {
                    LinkText(article: article, isStored: model.library.pageTextIDs.contains(article.id))
                } else if reader.previewArticle == article.id {
                    PagePreview(article: article, isStored: model.library.pageTextIDs.contains(article.id))
                } else {
                    Paragraphs(text: article.text.isEmpty ? "No text in the feed." : article.text)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(article.id)
    }
}

/// The text of the source page instead of the feed text (P), or how loading it goes.
struct PagePreview: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader
    let article: Article
    /// Passed in, so the preview isn't drawn again on every change of the library.
    let isStored: Bool
    /// Read from its file once the text is stored (`ArticleDetail` gives every article a view of its own).
    @State private var text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isStored {
                // An earlier failure doesn't show while the preferred view waits to load the page again.
                PageLoadStatus(phase: reader.waitingArticle == article.id ? nil : model.pageStatus[article.id]?.phase)
            } else if let text {
                Label("Text of the source page · P shows the feed text", systemImage: "doc.plaintext")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PageTextBody(text: text)
            }
        }
        .task(id: isStored) {
            if isStored {
                text = await model.pageText(article.id)
                if text == nil {
                    // Its file was gone: load the page again.
                    model.loadPage(article.id)
                }
            }
        }
    }
}

/// "Preview" (P) – "Reload Page" on a saved link – and "Summarize Page" (T).
struct PageButtons: View {
    @Environment(AppModel.self) private var model
    @Environment(MacServices.self) private var mac
    @Environment(Reader.self) private var reader
    let article: Article

    var body: some View {
        if article.isSavedLink {
            Button("Reload Page", systemImage: "arrow.clockwise") { reader.reloadPage(article.id) }
                .help("P: load the page again, after accepting cookies or logging in with V")
                .disabled(model.pageStatus[article.id]?.isRunning == true)
        } else {
            Toggle(
                "Preview", systemImage: "doc.plaintext",
                isOn: Binding(
                    get: { reader.previewArticle == article.id },
                    set: { _ in reader.togglePreview(article.id) })
            )
            .toggleStyle(.button)
            .help("P")
        }
        Button("Summarize Page", systemImage: "sparkles") { reader.summarizePage(article.id) }
            .help("T")
            .disabled(!mac.canSummarizePage(article.id))
    }

}

/// "Save" (S): shows whether the article is saved – the list may be scrolled elsewhere – and saves it or removes it
/// from Saved, as S does on its row (the detail shows the row under the cursor).
struct SaveButton: View {
    @Environment(Reader.self) private var reader
    let article: Article

    var body: some View {
        Toggle(
            article.isSaved ? "Saved" : "Save", systemImage: article.isSaved ? "bookmark.fill" : "bookmark",
            isOn: Binding(
                get: { article.isSaved },
                set: { _ in
                    if let cursor = reader.cursor {
                        reader.toggleSaved(cursor)
                    }
                })
        )
        .toggleStyle(.button)
        .help(article.isSaved ? "S: remove from Saved" : "S: save for later")
    }
}

/// The text of a saved link's page: it has no feed text. Its page loading (again) or why that failed shows above it,
/// unless the page summary shows it (T, or Save Link… with AI).
struct LinkText: View {
    @Environment(AppModel.self) private var model
    let article: Article
    /// Passed in, so the text isn't drawn again on every change of the library.
    let isStored: Bool
    /// Read from its file when stored, and again once the page was loaded again (P).
    @State private var text: String?

    var body: some View {
        let work = model.pageStatus[article.id]
        let isLoading = work?.phase == .loading
        VStack(alignment: .leading, spacing: 14) {
            if let work, !work.summary {
                PageLoadStatus(phase: work.phase)
            }
            if let text, isStored {
                PageTextBody(text: text)
            } else if !isStored && !isLoading {
                Text("The text of the page isn't loaded. Press P to load it.")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: [isStored, isLoading]) {
            if isStored && !isLoading {
                text = await model.pageText(article.id)
            }
        }
    }
}

/// "Open in Feedini" and "Open in Browser", the default way first.
struct OpenButtons: View {
    @Environment(Reader.self) private var reader
    let url: URL

    var body: some View {
        HStack {
            if reader.opensInWindow {
                windowButton.keyboardShortcut(.defaultAction)
                browserButton
            } else {
                browserButton.keyboardShortcut(.defaultAction)
                windowButton
            }
        }
        .controlSize(.regular)
    }

    private var windowButton: some View {
        Button("Open in Feedini", systemImage: "doc.richtext") { reader.open(url, inWindow: true) }
            .help(reader.opensInWindow ? "V / Enter" : "Shift+V / Shift+Enter")
    }

    private var browserButton: some View {
        Button("Open in Browser", systemImage: "safari") { reader.open(url, inWindow: false) }
            .help(reader.opensInWindow ? "Shift+V / Shift+Enter" : "V / Enter")
    }
}

/// An article's source page in the window, loaded on the user's request (V) or as the preferred view.
struct SourcePage: View {
    @Environment(Reader.self) private var reader
    let article: Article
    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back to Article", systemImage: "chevron.left") { reader.closePage() }
                    .help("Esc")
                Spacer()
                Text(url.host() ?? url.absoluteString)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Summarize Page", systemImage: "sparkles") { reader.summarizePage(article.id) }
                    .help("Back to the article with a summary of this page")
                Button("Open in Browser", systemImage: "safari") { reader.open(url, inWindow: false) }
            }
            .padding(8)
            .background(.bar)
            Divider()
            if reader.waitingArticle == article.id {
                // The preferred view loads the page once the cursor stays on the article.
                PageLoadStatus(phase: nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WebPageView(url: url, onEscape: { reader.closePage() }, onRefusedFocus: { reader.focusList() })
            }
        }
    }
}
