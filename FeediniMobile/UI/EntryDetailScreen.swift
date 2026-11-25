import SwiftUI

/// An opened row: a story with several articles (its summary and articles) or an article. Opening it reads it
/// (`ReadingSession.open`), and so does moving to the next or previous row (`DetailSteps`). A loose article the AI
/// puts into a story stays shown, as an article of the story.
struct EntryDetailScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(ReadingSession.self) private var session
    /// The row opened, then where next / previous moved. The route keeps the opened one, so Back returns to the list
    /// at once.
    @State private var row: ListRow
    /// Whether the row was opened (read): coming back to the screen (Back from an article of the story) reads nothing.
    @State private var isOpened = false

    init(row: ListRow) {
        _row = State(initialValue: row)
    }

    var body: some View {
        // Where its article is now: a loose article the AI put into a story stays shown, with its state.
        let shown = session.following(row)
        let entries = session.entries
        let steps = DetailSteps(previous: shown.neighbor(-1, in: entries), next: shown.neighbor(1, in: entries)) {
            row = $0
        }
        let entry = session.entry(shown.entryID)
        // Not a `Group`: it would hand `onAppear` to each branch, and a branch shown after a library change ("Gone")
        // would open the row again.
        ZStack {
            if let entry, case .story = shown, entry.isMultiArticle {
                StoryDetail(entry: entry, steps: steps)
                    .id(shown)
            } else if let entry, let article = entry.singleArticle(at: shown) {
                ArticleDetail(
                    article: article, entry: entry, row: shown, preferredView: model.preferences.articleView,
                    steps: steps
                )
                // The article, not the row: it keeps what it shows when it moves into a story.
                .id(article.id)
            } else {
                // The item, or its article, went away (a library change, retention).
                ContentUnavailableView("Gone", systemImage: "tray", description: Text("This item isn't here anymore."))
            }
        }
        .onAppear {
            if !isOpened {
                isOpened = true
                session.open(shown)
            }
        }
        .onChange(of: row) { session.open(row) }
    }
}

/// Next / previous in a detail: the rows next to the shown one where it is listed (`ListRow.neighbor`), and moving
/// there.
struct DetailSteps {
    let previous: ListRow?
    let next: ListRow?
    let move: @MainActor (ListRow) -> Void

    /// The two buttons, for the bottom bar.
    @MainActor @ViewBuilder var buttons: some View {
        Button("Previous", systemImage: "chevron.up") { previous.map(move) }
            .disabled(previous == nil)
        Button("Next", systemImage: "chevron.down") { next.map(move) }
            .disabled(next == nil)
    }
}

/// A story with several articles: its title, sources, summary and its articles.
private struct StoryDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(ReadingSession.self) private var session
    let entry: StoryEntry
    let steps: DetailSteps

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
                    EntryLink(row: .article(entry.id, article.id), link: article.link) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(article.title)
                                .font(.body.weight(article.isRead ? .regular : .semibold))
                            Text(
                                // The age first: a long feed name is cut, never the age.
                                [RelativeTime.short(article.date, now: .now), model.library.sourceTitle(of: article)]
                                    .compactMap { $0 }.joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
            if #available(iOS 26, *) {
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItemGroup(placement: .bottomBar) { steps.buttons }
            } else {
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    steps.buttons
                }
            }
        }
    }
}

/// An article: title, source, the TL;DR of its page or the summary of its story and the text from the feed or its
/// page, or its source page in Safari's view over them, switched in the bottom bar.
private struct ArticleDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(ReadingSession.self) private var session
    @Environment(Navigation.self) private var navigation
    let article: Article
    let entry: StoryEntry
    let row: ListRow
    let steps: DetailSteps
    /// The text the detail shows: at first what Settings say, then what the switch says.
    @State private var shown: Preferences.ArticleView
    /// The views the switch offers.
    private let views: [Preferences.ArticleView]

    init(
        article: Article, entry: StoryEntry, row: ListRow, preferredView: Preferences.ArticleView, steps: DetailSteps
    ) {
        self.article = article
        self.entry = entry
        self.row = row
        self.steps = steps
        views = Preferences.ArticleView.choices(for: article)
        _shown = State(initialValue: preferredView.shown(for: article))
    }

    var body: some View {
        text
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Up here: opening the article read it already, a reload is rare, and the bottom bar has no room left
                // on narrow iPhones.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if shown == .pageText {
                        Button("Reload Page", systemImage: "arrow.clockwise") { model.reloadPage(article.id) }
                            .disabled(model.pageStatus[article.id]?.isRunning == true)
                    }
                    Button(
                        article.isRead ? "Mark as Unread" : "Mark as Read",
                        systemImage: article.isRead ? "circle" : "checkmark.circle"
                    ) {
                        session.toggleRead(row)
                    }
                }
                // Saving on the left, next / previous, the switch on the right. Reload Page is up with Mark as Read
                // (a saved link shows its page text always).
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(
                        article.isSaved ? "Unsave" : "Save", systemImage: article.isSaved ? "bookmark.fill" : "bookmark"
                    ) {
                        session.toggleSaved(row)
                    }
                }
                if #available(iOS 26, *) {
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItemGroup(placement: .bottomBar) { steps.buttons }
                    if views.count > 1 {
                        ToolbarSpacer(.flexible, placement: .bottomBar)
                        // The segmented control has a background of its own; the toolbar's glass around it would draw
                        // a second outline.
                        ToolbarItem(placement: .bottomBar) { switcher }
                            .sharedBackgroundVisibility(.hidden)
                    }
                } else {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        steps.buttons
                        if views.count > 1 {
                            Spacer()
                            switcher
                        }
                    }
                }
            }
            .task(id: shown) {
                if shown == .pageText && !article.isSavedLink {
                    model.loadPage(article.id)
                }
            }
    }

    /// The switch's choice: the web page while it is open in Safari's view, else the text shown. Choosing the web page
    /// opens it over the text, which Done returns to.
    private var selection: Binding<Preferences.ArticleView> {
        Binding(
            get: { navigation.page != nil ? .webPage : shown },
            set: { view in
                if view == .webPage {
                    navigation.page = article.link
                } else {
                    shown = view
                }
            })
    }

    /// The switch between the views of the article.
    private var switcher: some View {
        Picker("Show", selection: selection) {
            ForEach(views, id: \.self) { view in
                Image(systemName: view.symbol)
                    .accessibilityLabel(view.title)
                    .tag(view)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var text: some View {
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
                if shown == .pageText {
                    PageTextSection(article: article, isStored: model.library.pageTextIDs.contains(article.id))
                } else {
                    Paragraphs(text: article.text.isEmpty ? "No text in the feed." : article.text)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The text of the source page – loaded on request or as the preferred view, then stored – or how loading it goes. A
/// saved link has only this text.
private struct PageTextSection: View {
    @Environment(AppModel.self) private var model
    let article: Article
    /// Passed in, so the text isn't read again on every change of the library.
    let isStored: Bool
    @State private var text: String?

    var body: some View {
        let work = model.pageStatus[article.id]
        VStack(alignment: .leading, spacing: 14) {
            // Loading, or why it failed – also a failed reload over the stored text, which stays.
            if let work {
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
                if text == nil && !article.isSavedLink {
                    // Its file was gone: load the page again.
                    model.loadPage(article.id)
                }
            }
        }
    }
}

extension Preferences.ArticleView {
    var title: String {
        switch self {
        case .feedText: "Feed Text"
        case .pageText: "Page Text"
        case .webPage: "Web Page"
        }
    }

    var symbol: String {
        switch self {
        case .feedText: "text.alignleft"
        case .pageText: "doc.plaintext"
        case .webPage: "globe"
        }
    }
}
