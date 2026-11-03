# Feedini

Feedini is a native macOS RSS reader, driven by the keyboard, that groups articles from many feeds into stories and
topics and summarizes them with AI (through the local `claude` CLI). Without AI it is a plain, fast feed reader.

## Commands

```bash
make build    # xcodebuild Debug build into build/DerivedData
make test     # Swift Testing unit tests (hosted by the app)
make coverage # tests + line coverage report of the app target (result bundle build/Test.xcresult)
make run      # build, kill a running instance, open the app
make install  # Release build into ~/Applications (INSTALL_DIR=…), restart it; make uninstall removes it
make format   # xcrun swift-format, in place
make lint     # xcrun swift-format lint --strict
make clean    # rm -rf build
```

Run `make lint test` after every change. `CONFIG=Release make build` builds Release.

CI (`.github/workflows/ci.yml`, GitHub Actions on pushes to `main` and pull requests) runs `make lint`,
`make coverage` and `CONFIG=Release make build` in one job; the steps run even after an earlier one fails, and the
result bundle is uploaded when something fails. It uses the `xcode-27` runner image (a preview; `macos-26` only has
Xcode 26).

## Toolchain and project

- Xcode 27 / Swift 6.4, deployment target macOS 15, Swift 6 language mode (complete strict concurrency).
- `Feedini.xcodeproj` is hand-written (`objectVersion = 77`) with file-system synchronized root groups for `Feedini/`
  and `FeediniTests/`: new files are picked up automatically, do not add file references to `project.pbxproj`. Edit
  the pbxproj only for build settings / targets; keep object IDs in the `FEED…` scheme.
- Shared scheme `Feedini` (`xcshareddata/xcschemes/Feedini.xcscheme`) so `xcodebuild -scheme Feedini` works; it
  collects coverage for the app target only.
- Bundle ID `cz.jsyrovy.feedini`, a regular app (`LSUIElement = NO`), generated Info.plist, App Sandbox off (the app
  runs the `claude` CLI, which a sandboxed app can't), no hardened runtime yet, ad-hoc signing ("Sign to Run Locally",
  no team). App Transport Security keeps its defaults (no exceptions): only HTTPS feeds work.
- The app icon (`Feedini/AppIcon.icon`, Icon Composer format) is a pixel-art top hat (32 × 32 grid) with the RSS
  symbol cut out of its crown: a black hat on cream in the light appearance, a cream hat on charcoal in the dark one
  (`fill-specializations`, `image-name-specializations`). Layers: outline, brim, band, crown, without glass (it
  blurs the pixels). The menu bar item shows the same hat, 16 × 16 pixels without the RSS symbol, as a template
  image (`Assets.xcassets/MenuBarIcon`, @1x and @2x).
- Nothing may be installed on the dev machine (no XcodeGen, SwiftLint, xcbeautify, …). Formatting is `swift-format`
  from the toolchain, configured in `.swift-format` (4 spaces, 120 columns).

## Structure

```
Feedini/
  App/        @main entry (FeediniMain → FeediniApp with the main Window, Settings and MenuBarExtra, or an empty
              TestHostApp under tests), AppDelegate (owns the model, saves at quit, Dock icon only with the window,
              refresh after wake), AppModel (library on the main actor, saving, refreshing, the AI queues),
              Preferences (UserDefaults), LoginItem (SMAppService), RuntimeEnvironment, Log (os.Logger categories)
  Model/      Feed, Article, Story (+ Summary), Topic, Tombstone (Codable, Sendable), Library (all of them, read
              state, removing feeds), Folder (+ Library's folder operations, SidebarDrag: dragging feeds and
              folders), Saved (SavedItem, Library's saving, names of removed feeds), AIUsage (AI calls per day),
              StoryList (pure: entries, filtering by the sidebar selection, Saved, unread counts), ReadRules (pure:
              what visiting a row and M do; ListRow), UndoHistory (pure: ReadingState, the steps of ⌘Z / ⇧⌘Z)
  Store/      LibraryStore (versioned JSON file, debounced atomic saving, page texts as files of their own),
              Retention (pure: what is forgotten when)
  Feeds/      FeedFetcher (URLSession, concurrent, timeouts, ETag / Last-Modified), FeedParser (XMLParser: RSS
              0.9x / 1.0 / 2.0, Atom), HTMLText (HTML → plain text, excerpts), FeedLanguage (<language> or
              NLLanguageRecognizer), OPML (import / export), FeedSubscriber (checks an address or OPML entries before
              adding: HTTPS only, a real feed, not subscribed yet), PageExtractor (a source page's text in a hidden
              WKWebView: PageScript, PageText, PageExtracting)
  Refresh/    RefreshCoordinator (download + parse off the main actor), FeedMerge (pure: new articles, dedupe against
              known articles and tombstones), RefreshScheduler (periodic loop with an injected sleep)
  AI/         ClaudeLocator (binary lookup), ProcessRunner (subprocess with stdin, timeout, process group),
              ClaudeClient (CLI arguments, envelope, errors), Prompts (system prompts + JSON schemas), AssignStep
              (payload with short IDs), Validation (pure: applying an assign answer), SummaryStep (pure: which
              stories, priority, payload, applying) + TopicTranslation, AIQueue (AICaller: one call with its
              recording; AssignQueue: serial batches, backoff; SummaryQueue: parallel batches, priority;
              LibraryHost, AIConfiguration), PageSummaryStep (pure: page summary request, applying),
              PageSummaryQueue (P / T on request: loading pages, summarizing them), AIStatus (@Observable state,
              stories being summarized, pages being loaded or summarized, recent calls), OutputLanguage (names,
              choices)
  Backup/     BackupFile (pure: the file format, names, compression; BackupError), BackupPlan (pure: when a backup
              is due, thinning out; BackupFrequency), BackupStore (the files in iCloud Drive, file coordination),
              Backups (@Observable: automatic backups, Back Up Now, reading backups), BackedUpSettings (the settings
              in a backup, `Preferences.apply`)
  Support/    OneShotSignal (an awaitable one-time event), ConcurrentMap (`concurrentMap(limit:)`, order kept)
  Debug/      Debug builds only (`#if DEBUG`): DebugCommands (the Debug menu: reorganize all as a cold start,
              rewrite summaries, add made-up articles to a "Debug" feed)
  UI/         MainWindow (NavigationSplitView), Sidebar (+ folders, dragging), FolderViews (FolderNameSheet,
              MoveToFolderMenu), Removal (confirming the removal of feeds or a folder), StoryListView (keys, status
              bar), StoryRow / ArticleRow,
              DetailView (StoryDetail, ArticleDetail + PagePreview + PageButtons, SourcePage), SummaryView (+
              PageSummaryView), WebPageView (WKWebView), Reader (window state: selection, cursor, expanded stories,
              kept entries, the shown page or page text, the shortcuts sheet, the undo history), UndoCommands (Edit →
              Undo / Redo), KeyboardNavigation (pure: what a key does), ShortcutHelp (pure: the shortcuts by group)
              + ShortcutsView (the ? sheet), RelativeTime, SettingsView (tabs) + FeedsSettings + GeneralSettings +
              AISettings + BackupSettings, RestoreSheet, BackupCommands (File menu), MenuBarContent (+ MenuBarLabel)
FeediniTests/ Swift Testing tests, mirroring the app folders
  Fixtures/   claude CLI envelopes (success, is_error, no structured_output, wrong shape; anonymized IDs), feeds
              with made-up text but the structure of real ones (RSS 0.91 / 1.0 / 2.0, Atom, long HTML,
              content:encoded, CDATA, HTML entities, windows-1250, duplicates, missing dates), a web page, an OPML
              file, article pages with made-up text for the extraction (`page-*.html`: a cookie consent overlay, an
              article in divs, `main` with a menu and navigation, JSON-LD only, no article)
  Support/    Fixture loader, ManualSleeper, StubURLProtocol (canned HTTP replies by URL), FakeCommandRunner
              (canned CLI replies, recorded calls), FakePageExtractor (canned page texts, recorded requests),
              TestLibraryHost + `ClaudeLocator.stub` + `AppModel.test()` (fake claude and pages), model stubs
              (`referenceDate`, `Article.stub`, …)
```

## Conventions

- Everything in the repo (code, comments, docs, commit messages, prompts, UI texts) is in English.
- No third-party dependencies.
- Swift 6 strict concurrency: UI types are `@MainActor`; data crossing actors is `Sendable`. Default actor isolation
  is left at `nonisolated` (no `SWIFT_DEFAULT_ACTOR_ISOLATION`), and functions that must run off the main actor are
  marked `@concurrent`. Locks: `Mutex` (Synchronization).
- The UI never waits on the network or a subprocess.
- Logic lives in pure types with ~100 % meaningful test coverage; `App/` and `UI/` are wiring and layout, checked by
  running the app (see "Testing").
- Data comes from the feeds. A web page is loaded only on the user's explicit request, never automatically: the
  source page opened with V, its text for P (preview) and T (summary). Only T sends a page's text to the AI.
- Privacy: the page loads with the user's cookies and logins (the default website data store), so its text may
  include what the site shows about the user ("Logged in as …"). Choosing the article container (`article`, `main`)
  leaves most of that out, but not reliably.
- AI is always optional; an AI failure never blocks reading.
- Nothing secret or personal in the repo: no API keys, personal paths or names, `claude` outputs with session IDs.
- Feed fixtures have the structure of real feeds but made-up text (no copies of other people's articles).

## Design decisions

- Native macOS app in Swift, UI in English, styled after Feedly-like readers but driven by the keyboard (J/K).
- Feeds: added and removed by URL in Settings, plus OPML import and export. The default feed list is empty.
- HTTPS only. ATS keeps its defaults; an `http://` address is tried as `https://` and rejected if that fails ("Only
  HTTPS feeds are supported"). A feed that redirects from HTTPS to HTTP is blocked by ATS; the error must say so.
- Unread articles are kept forever; they only go away when read or marked as read.
- Read articles are remembered as tombstones (feed + guid / link) while they are still in the feed plus a margin, so
  a refresh doesn't bring them back. Read stories stay (hidden) for `attachWindow` (72 h) so that a new article
  about the same event joins the known story, which comes back as unread with "+1 new".
- Storage: one versioned JSON file in `~/Library/Application Support/Feedini/` (Codable, atomic writes, debounced
  saving). No SwiftData (testability, migrations, friction with strict concurrency). If the data outgrows it, only
  the store moves to SQLite (system C API).
- AI runs only through the local `claude` CLI (`-p`, `--json-schema`, `structured_output`); there is no direct API in
  v1. Hence no App Sandbox and no Mac App Store. Without the CLI Feedini is a plain reader and says why AI is off.
- AI never blocks display: new articles show right away, grouping and summaries arrive later. The work is split by
  task, not by data: an assign step (new articles → existing or new stories and topics, no summaries) and a summary
  step (only where useful, in parallel, afterwards). Splitting by data (per feed, per time slice) would break the
  cross-feed grouping that is the point of the AI.
- One event = one story card, including follow-up articles about its details (e.g. a whole product launch). Topics
  are kept stable by passing the existing ones (of unread stories) to the AI, which reuses them or creates new ones.
- Summaries only where they add something: stories with several articles always; a single article only as chosen in
  Settings → AI ("Summarize single articles": never (default), in other languages than the summary language (then it
  is a translation), always). Otherwise a single article shows its own title and excerpt.
- Most feeds carry only the first lines of an article (a median of 200–330 characters for most of the test feeds).
  P shows the text of the source page instead, T a TL;DR of it; both only on request, on a single article.
- After closing the window the app keeps running in the menu bar (`.accessory`) and keeps refreshing, so opening it
  shows everything processed. With the window open it is a regular app with a Dock icon.
- Folders ("Folders" in the UI, not "categories", which would blur with the AI topics) group feeds by hand: one
  level, a feed in at most one folder, folders in the user's order. They don't reach the AI.

## Reading model

Three columns: sidebar (All, Saved, topics by unread count, folders with their feeds, feeds in no folder), story
list (newest first), detail.

- A story with one article behaves like an article. A story with several articles has an AI title, a summary and
  source labels; its articles are collapsed in the list. An expanded story shows them indented below it, and J/K
  walks through them.
- Moving onto an item (click, arrows, J/K) marks it read. A collapsed story is marked read as a whole (the summary
  covered all its articles); in an expanded story articles are marked one by one, and the story is read when all
  its articles are. M toggles read / unread (on a collapsed story: all its articles).
- A read item doesn't vanish from the current list (no jumping under the cursor); it goes away when the sidebar
  selection changes or on refresh.
- S saves the item under the cursor for later, S again removes it from Saved. On an article row, a story with one
  article or a loose article it saves the article; on the row of a story with several articles (collapsed or
  expanded) the whole story. Saved items have a bookmark in every list.
- Saved (in the sidebar under All, with the number of saved items, not in the menu bar count) shows every saved
  item, read or not, most recently saved first: saving happens on items that moving onto them already read. A saved
  article is shown on its own even when its story has several articles, with "Part of: <story title>" (also after
  the AI puts a saved loose article into a story). An item removed from Saved stays in its place until the selection
  changes or a refresh; Shift+A does nothing there. Saved items are never forgotten, a saved story keeps its summary
  up to date even when read, and removing a feed keeps its saved articles.
- The detail shows the text from the feed. V / Enter opens the source page the default way, Shift+V / Shift+Enter
  the other way (Settings → General: "Feedini window" (default) or "Default browser"). On a collapsed story with
  several articles V / Enter expands it (there is no single source page) and Shift+V / Shift+Enter does nothing.
- In the window the page replaces the feed text in the detail; V / Enter again or Esc returns to the feed text.
- P (preview) shows the text of the source page instead of the feed text (loaded the first time, then stored); P
  again returns to the feed text. A text cut at `PageText.maxLength` ends with a pointer to V. Works without AI.
- T (TL;DR) summarizes the source page with AI: a box above the text with the TL;DR and, for longer texts, details
  as bullet points. It replaces the AI gist of the feed text of a one-article story (it is more complete). T on a
  current summary does nothing; after a change of the summary language it writes a new one from the stored text.
  From the source page in the window, T (or its "Summarize Page" button) returns to the text with the summary.
- Shift+S saves the item like S (never removes it) and on an article with a link prepares its TL;DR in the
  background, as T would, without changing the detail: P and T are then instant, and the text stays even if the page
  goes away. Without AI the page text is still stored; on a story with several articles it only saves. While it runs
  the row shows ✨, a failure (AI off, a consent or login wall, an error) ⚠︎ with the message, in every list; only T
  tries again.
- ⌘Z takes back reading and saving in the main window, one step at a time, ⇧⌘Z does it again (a new step clears
  that). A step is every change of reading or saving: moving onto an unread item, M, Shift+A (all of it at once), S,
  Shift+S (the saving; the page work goes on). It puts back exactly the state before (also the "+1 new" marks), shows
  the item's row without reading it, keeps it in the list and doesn't change the sidebar selection. The menu names
  the step ("Undo Mark as Read"). The history lives as long as the app (also with the window closed), at most
  `UndoHistory.limit` (100) steps; a step whose items are gone (a removed feed, retention) is skipped. Steps that
  change nothing (moving onto a read item) aren't recorded. Elsewhere – Settings, sheets, text fields – ⌘Z is the
  usual text undo. Sidebar, folder and settings actions can't be undone.
- P and T work like Shift+V: on an article row or a story with one article, with a link; on a collapsed story with
  several articles they do nothing. Opening the page in the window (V) forgets its stored text, so the next P / T
  loads it again – after the user accepted cookies or logged in there.
- ? shows the keyboard shortcuts (`ShortcutsView`, a sheet; Esc, ? or Done close it), also from Help → Keyboard
  Shortcuts (without a key equivalent: a plain key would fire in text fields, ⌘? searches the Help menu). T is
  grayed with the reason while AI can't run. The empty detail says "Press ? for keyboard shortcuts."

| Key | Action |
|---|---|
| J / ↓ | next item (story; article inside an expanded story) |
| K / ↑ | previous item |
| L / → | expand the story |
| H / ← / Esc | collapse the story (from an article: jump to its story) |
| V / Enter | open the source page the default way |
| Shift+V / Shift+Enter | open the source page the other way |
| P | the text of the source page instead of the feed text, again: back |
| T | TL;DR of the source page (AI) |
| Shift+S | save for later and prepare the TL;DR of the source page |
| M | toggle read / unread |
| S | save for later / remove from Saved |
| R | refresh now |
| Shift+A | mark everything in the current selection (All, topic, folder, feed; not Saved) as read |
| ? | keyboard shortcuts |
| ⌘Z / ⇧⌘Z | undo / redo the last reading or saving |
| ⌘, | settings |

Keys work in the list. While the web page has focus, only Esc works (it returns focus to the list).

Implementation:

- `StoryList.allEntries` turns the library into `StoryEntry`s: every story, plus every article no story holds yet
  (`.loose`, shown like a one-article story), newest first by their newest article. A one-article story uses the
  article's title. `entries(_:matching:folders:keeping:)` filters by the sidebar selection (a feed shows every story
  with an article of it, a folder every story with an article of one of its feeds) and hides read entries unless
  they are in `keeping`. Counts match what is shown: a story counts once in a folder, even with articles of several
  of its feeds.
- `StoryList.savedEntries` builds Saved from the entries: saved stories as their entry, saved articles as
  `.savedArticle` entries (`partOf` for a story with several articles; a one-article story lends its title and
  summary). `StoryEntry.savedItem(at:)` says what S saves on a row. `AppModel` caches them with the other entries;
  reading and saving patch the entries (`StoryList.updateReadingState`) and saving rebuilds only Saved.
  `Reader.unsaved` remembers the save dates of entries removed while Saved is shown, so they keep their place
  (`AppModel.savedEntries(keeping:)`; `entry(_:)` builds a `.savedArticle` entry on demand, saved or not).
- `Reader` (main actor, UI state) keeps the cursor (`ListRow`: a story or an article of an expanded story). Moving
  onto a row (`visit`) applies `ReadRules` and adds the entry to `kept`, so it stays until the sidebar selection
  changes or a refresh ends (then only the entry under the cursor stays). Shift+A doesn't keep anything: the list
  empties. M keeps the entry too.
- `KeyboardNavigation.action` decides what a key does from the cursor, the rows, the expanded stories, the default
  way of opening pages and the shown page; `Reader.handle` carries it out. The story list's `onKeyPress` maps keys
  (plain keys only – with ⌘ / ⌃ / ⌥ they go to the menus); ? is matched as a character, not a key, so it works on
  any keyboard layout. A double click opens like V / Enter.
- `Reader.recording` snapshots the `ReadingState` (read and save dates of the articles, save date and "new" marks of
  their stories) before a change and records it in `UndoHistory` (its callers only make changes that change
  something); undo and redo are `Library.restore`, which returns the replaced state for the other stack
  (`AppModel.restore` patches the cached entries like reading and saving). `UndoCommands` replaces Edit → Undo / Redo: while the main
  window is key (`Reader.isMainWindowKey`, set by `AppDelegate` from the key window notifications) they go to the
  reader, otherwise `undo:` / `redo:` go to the responder chain.
- `ShortcutHelp.item(for:)` switches over every `ListKey` (`CaseIterable`), so a new key doesn't compile without
  its line in the help.
- `Reader.shown` is what the detail shows instead of the feed text: the source page (V) or its text (P), never both.
  Moving, a new sidebar selection and Shift+A reset it.
- The source page (`WebPageView`): a `WKWebView` with the default persistent website data store (logins and cookies
  work), JavaScript on, no script message handlers. Link clicks and new windows open in the default browser. Esc in
  the page (`EscapableWebView`) returns to the feed text and focuses the list (`Reader.listFocusRequests`).
- When the AI puts a loose article into a story, the entry's ID changes (`.loose` → `.story`). `Reader` follows it
  on every library change (`AppModel.onLibraryChange`): the cursor moves to the article inside the (expanded) story,
  or to its one-article story, and kept entries stay kept – nothing is marked read by that.
- Summaries in the detail (`SummaryView`): a story with several articles shows its summary between the title and
  the articles; a one-article story that needs one shows it above the feed text. Lines starting with "- "
  become bullet points. Without a summary yet: "Summarizing…" (or the error after repeated failures); an out-of-date
  one stays with "Updating summary…" while the AI works.
- AI in the list: a loose article shows ✨ while the AI organizes (`AIStatus.organizing`); the status bar shows
  "Organizing N articles…", "Summarizing N stories…", "Summarizing page…" or "AI unavailable: …" next to the
  refresh state. Stories
  from several feeds have an accent bar and source labels; "+N new" marks articles that joined a read story.
- `AppModel` holds the `Library`; every change goes through `update(_:)`, which hands a copy to `LibraryStore.save`
  in order. The entries are cached with an index by ID (`AppModel.entry(_:)`) and the unread counts
  (`unreadCounts`, used by the sidebar and the menu bar) for one summary language and choice of single-article
  summaries; the cache is rebuilt only when the articles or stories change or one of those does. Reading and saving
  (and their undo) patch it and don't notify the reader (they never move articles into stories).

## Feeds

- `FeedFetcher` downloads with an ephemeral `URLSession` without a cache (20 s per request, 60 s per resource,
  `User-Agent: Feedini/…`), sends `If-None-Match` / `If-Modified-Since` from the previous download (304 →
  `notModified`) and ignores the `Content-Type` (some feeds are served as `text/html`). `fetchAll` runs 6 downloads
  at a time; every feed gets its own outcome, so one failing feed never affects the others. Failures are
  `FetchError`s with a message for the user – an ATS block (a redirect from HTTPS to HTTP) says so instead of a
  generic network error.
- `FeedParser` reads RSS 0.9x / 2.0 (no namespace), RSS 1.0 (RDF) and Atom with `XMLParser` and namespace
  processing; the root element decides the format, anything else (a web page) is `FeedParserError.notAFeed`, also
  an HTML page that breaks the parser before its root element (a lowercase `<!doctype html>`). The encoding comes
  from the XML declaration (libxml2), never from the HTTP header.
- A feed that doesn't parse completely is repaired on the byte level and parsed again (`FeedParser.repairXML`):
  whitespace before the declaration, HTML named entities (`&nbsp;` → `&#160;`) and bare `&`. The repaired parse
  wins unless it gives fewer items; a feed that stays broken in the middle keeps the items read up to there.
- An item's key is the guid / Atom id, else its link, else its title; items without any are dropped, duplicate keys
  keep the first. The title falls back to the start of the text. Dates: `pubDate` (RFC 822 variants), `dc:date`,
  Atom `published`, else `updated`. Author: `dc:creator`, the name in RSS `author` (`mail (Name)`), Atom
  `author/name`. Links are resolved against the feed URL; only `http(s)` links are kept.
- Text: `content:encoded` / Atom `content` when present, else `description` / `summary`, converted by
  `HTMLText.plainText` (paragraphs as blank lines, `<br><br>` too, list items with "• ", scripts, styles and
  comments dropped, entities decoded) and cut to `FeedParser.maxTextLength` (10 000 characters, ending in "…").
- `OPML.parse` returns every outline with an `xmlUrl` (any case), nested ones (categories) included, without
  duplicates (the first wins), URLs as written – checking them is the importer's job. A feed's folder is the name of
  the nearest named category; deeper levels are flattened. Import puts new feeds into the folder of that name
  (ignoring case), adding it when needed; feeds already subscribed aren't moved. `OPML.export` writes OPML 2.0 with
  folders as categories in their order (empty ones left out), then the feeds in no folder.
- `FeedLanguage`: the feed's `<language>` / `dc:language` / Atom `xml:lang` reduced to the primary code (`cs-CZ` →
  `cs`); without one, `NLLanguageRecognizer` on the title and the start of the text (at least 50 % sure).

### Source pages (P, T)

- `PageExtractor` (main actor) loads a page in its own hidden `WKWebView` (1200 × 900, the default website data
  store shared with `WebPageView`, JavaScript on, images, media and fonts blocked by a content rule list compiled
  once), waits for `didFinish` plus 1 s (a new navigation – a script redirect – restarts the wait), runs
  `PageScript.extract` and gives up after 20 s. HTTP errors of the main frame, load failures (worded by
  `FetchError`) and timeouts are `PageError`s with a message for the user.
- `PageScript.extract` only reads the page. It leaves out overlays (`position: fixed`, dialogs, hidden elements,
  ids / classes of consent tools: a cookie dialog otherwise wins with the most text), navigation, headers, footers,
  forms, figures, comments and share buttons. The container is the biggest `[itemprop=articleBody]`, else `article`,
  else `main` (each with at least 500 characters), else the element with the most paragraph text, else the body.
  Its blocks (by computed `display`) become paragraphs separated by blank lines, `<br>` a line break (two a
  paragraph), list items "• " lines, `pre` stays as it is; blocks that are mostly link text (menus, lists of other
  articles) are dropped. JSON-LD `articleBody` is only a fallback under 500 characters (it has no paragraphs). It
  returns at most twice `PageText.maxLength`.
- `PageText.clean` (pure) collapses whitespace, drops empty lines and cuts at `maxLength` (100 000 characters, a
  safeguard against a failed extraction, not a model limit; the longest article in the lab had 37 000); less than
  `minLength` (100) is `PageError.noText`.
- Measured on nine Czech and English feeds: 1.8–2.5 s per page; menus that the container's `innerText` kept are
  gone. A site that redirects to its consent page on the server (iDNES) gives the consent text until the user
  accepts it in the window (V); the AI then answers `not_article`.

## Running in the background

- Closing the main window doesn't quit (`applicationShouldTerminateAfterLastWindowClosed` is false): the model
  lives in `AppDelegate`, so refreshing, organizing and summarizing go on. With the window open Feedini is a
  regular app (Dock icon, menus); when it closes it switches to `.accessory` and only the menu bar item stays
  (`AppDelegate.mainWindowIsOpen`, called from `MainWindow` appearing and disappearing).
- Menu bar item (`MenuBarExtra`, menu style): the hat with the number of unread stories (optional), and a menu with
  the count, "Open Feedini" (⌘O), "Refresh Now" (⌘R), the time of the last refresh, the AI status (always shown:
  "AI: ready", "AI: off", or what it is doing / why it can't run), a backup problem if there is one, Settings and
  Quit.
- After the Mac wakes from sleep (`NSWorkspace.didWakeNotification`) the feeds are refreshed right away.
- Quitting waits for pending changes to be saved (`applicationShouldTerminate` → `AppModel.flush`). `pkill` (as in
  `make run`) skips that; quit with ⌘Q or `osascript -e 'tell application id "cz.jsyrovy.feedini" to quit'` when
  the last seconds of reading matter.

## Folders

- `Library.folders` (in the sidebar's order) and `Feed.folderID`, which is `nil` or an existing folder: removing a
  folder clears it, `moveFeeds` ignores unknown folders and loading drops them (`repairFolders`). Removing a folder
  keeps its feeds, in no folder (after a confirmation that says how many).
- Names are one line (runs of whitespace and line breaks become one space, trimmed), not empty, at most
  `Folder.maxNameLength` (40) characters – the sidebar shows about 30, and menus and pickers grow with the longest
  name – and unique ignoring case (`FolderNameError`). A name typed by the user that breaks a rule is refused, never
  merged or cut. OPML categories and names in a loaded file are shortened instead (`Folder.shortenedName`: 39
  characters + "…"); loading also numbers names that clash ("Name 2").
- Sidebar: a folder is a `DisclosureGroup` (collapsed ones in `Preferences.collapsedFolders`, window state, not in
  the library) with its feeds by title; feeds in no folder follow by title. A folder can be selected (Shift+A
  marks it all read); a selected folder, feed or topic that goes away falls back to All (`Library.contains`).
- Moving: dragging (`SidebarDrag`, carried as text `feedini-feed:<id>` / `feedini-folder:<id>`) puts the dragged
  item where the target is – a feed into the target folder, the target feed's folder or no folder; a folder to the
  target folder's place (after it when moving down), or to the end onto a feed in no folder. The context menu has
  New Folder…, Rename…, Move Up / Down, Delete Folder… (folders), Move to Folder ▸ and Remove Feed… (feeds); Delete
  removes the selected feed or folder. Both ask first (`Removal`, the same dialog as Settings → Feeds). There are no
  other keys.
- Settings → Feeds: the folder for a new feed next to the address, a Folder column, Move to Folder ▸ for the
  selected feeds, New Folder….
- `AppModel` caches the folder of every feed with the entries; moving feeds only recounts (`EntriesCache.setFolders`).

## Settings

- **Feeds** (`FeedsSettings`): the feeds with the state of their last download (`lastChecked` or `lastError`), an
  address field, removal (with confirmation; articles go too, saved ones stay and the dialog says how many), OPML
  import and export. Adding goes through
  `FeedSubscriber`: a missing scheme and `http://` / `feed://` become `https://`; an `http://` address whose HTTPS
  variant fails is rejected with "Over HTTPS: <the reason> Only HTTPS feeds are supported." (the reason first: it
  is the real cause, HTTP isn't tried); the address must give an RSS / Atom feed and
  not be subscribed yet (`isSame` ignores the case of scheme and host and a trailing slash). The first download is
  merged right away (`AppModel.subscribe`), so the articles appear without another download. OPML import checks the
  entries 6 at a time, adds the good ones in file order and lists the others with the reason; "Copy Errors" puts
  the failed ones (not those already followed) on the clipboard as text with their feed and site addresses
  (`ImportResult.errorReport`), to pass on to whoever looks into them.
- **General** (`GeneralSettings`, `Preferences`): refresh interval (`refreshMinutes`: 5 / 15 / 30 / 60, default 15),
  where V / Enter opens pages (`pageOpening`: `window` (default) / `browser`), open at login (`LoginItem`, the
  system's login items via `SMAppService.mainApp`; its state is read from the system, not stored) and the unread
  count in the menu bar (`showsUnreadCount`, on by default). Values that aren't offered fall back to the default.
- **AI** (`AISettings`): the summary language ("System (…)" first, then common languages by English name with
  their own name), which single articles are summarized (Never / In other languages / Always), on / off, the state (ready, organizing, unavailable and why), the path to claude (empty =
  found automatically, the found path is shown as the placeholder), the models and effort, and the last 20 calls
  with duration and cost or the error, and the usage: calls, time and cost per day for the last 7 days and the
  total of the kept 30 (`Library.usage`, `AIUsageDay`, recorded with every call claude actually ran). A typed path
  to claude is used once it is submitted or Settings close, not on every keystroke.
- **Backup** (`BackupSettings`): automatic backups on / off (`backsUp`, off by default) and how often
  (`backupFrequency`: hourly / daily (default) / weekly), the last backup (shown once known) or its problem, Back Up
  Now, Restore… and Show in Finder. See "Backup".

## Refresh

- `RefreshScheduler` (main actor) refreshes at start and then `interval` after each refresh finished (Settings →
  General: 5 / 15 / 30 / 60 min, default 15), so refreshes never overlap. `refreshNow()` cuts the wait short and is
  ignored while a refresh runs; `setInterval(_:)` restarts the current wait with the new length. Tested with
  `ManualSleeper`.
- `RefreshCoordinator.refresh` (`@concurrent`) downloads all feeds (`FeedFetcher.fetchAll`) and parses them into
  `FeedRefresh` values (`updated` / `notModified` / `failed(message)`); `FeedMerge.merge` (pure) applies them to the
  library on the main actor and returns the new article IDs.
- Merging: items with a known key are left alone (no edits after the fact); items with a tombstone only refresh its
  `lastSeen`; the rest become unread articles with `firstSeen = now`. The first download of a feed (no
  `lastSuccess` yet) turns items older than `FeedMerge.firstDownloadMaxAge` (7 days) into tombstones, so adding a
  feed with its whole history doesn't flood the list. A failed feed only records `lastError`.
- `Feed.lastSuccess` is the last full (200) download – tombstones are judged against it, so a feed answering "304
  Not Modified" for days keeps them; `lastChecked` includes 304s (shown in Settings).

## AI pipeline

### claude CLI

```bash
claude -p --model <model> --effort <effort> --system-prompt <prompt> --safe-mode --tools "" \
  --no-session-persistence --output-format json --json-schema <schema> "Process the input."   < payload.json
```

- `--tools ""` (no tools at all) and `--safe-mode` (no user customizations, hooks or MCP servers): the content of
  articles is data, and with nothing to call a prompt injection in a feed can't do anything. `--no-session-persistence`
  keeps the calls out of the user's session history. The payload goes to stdin, never into arguments.
- `ClaudeLocator` looks in `~/.local/bin` (native installer), `/opt/homebrew/bin`, `/usr/local/bin`, then `PATH`
  (apps started from the Finder don't get the shell `PATH`); a path set in Settings wins. Looked up on every call.
- The envelope (verified with claude 2.1.312) is one JSON object: `type: "result"`, `is_error`, `subtype`, `result`
  (text; the error message when `is_error`), `structured_output` (the object matching the schema), `duration_ms`,
  `duration_api_ms`, `total_cost_usd`, `usage.output_tokens`, plus `session_id` / `uuid` (never stored or committed).
  `ClaudeClient.parse` maps everything else to a `ClaudeError` with a message for the user; `notFound` and
  `launchFailed` are setup problems, the rest is worth retrying (`isTransient`).
- `ProcessRunner` (from buddr): stdin is a pipe written from a background thread with `F_SETNOSIGPIPE` (a command
  that exits without reading can't kill the app), a hard timeout that signals the whole process group, and output
  awaited at most `outputGracePeriod` after exit.
- The contract with the real CLI is not tested on CI; check it by hand after CLI updates (it costs a fraction of a
  cent with Haiku).

### Prompts

`Prompts` holds the system prompts and schemas in English; the output language is a field of the payload
(`output_language`). They were tuned in a prompt lab (Python, outside the repo) over saved feed data: attaching new
articles to known stories (also across languages), topic stability with existing topics, cold start in batches,
summaries checked for invented facts. Change a prompt by testing it the same way first, then copy it unchanged.

### Assign step

- Payload (`AssignStep.payload`, pure): `output_language`, `topics` (those of unread stories), `stories` (every
  story whose newest article is younger than `attachWindow`, read ones included, with the titles and sources of
  their articles) and `new_articles` (source, title, published, a 600-character excerpt). IDs are short and per
  call (`a1`, `s1`, `t1`; `IDMap` maps them back), which saves tokens and makes validation simple.
- Answer: `attach` (story id + article ids), `new_topics` (key `n1`…, name, description), `new_stories` (title,
  topic id or key, article ids).
- `AssignValidation.apply` (pure) never trusts the answer: unknown IDs are dropped and an article used twice stays
  where it was first; left-out articles get a story of their own (title of the article, no topic); a topic is
  resolved by id, then new key, then – models sometimes write names – by name ignoring case, else it becomes a new
  topic with that name. An article joining a read story is put into its `newArticleIDs` ("+1 new"), which makes the
  story unread again. It returns metrics, which are logged.
- An article is "processed" once it belongs to a story; articles without one are shown on their own (`.loose`).

### Summary step

- A story needs a summary when it has several articles. A story with a single article needs one as
  `SingleArticleSummaries` says (`SummaryStep.needsSummary`): `never`, `otherLanguages` (the article's language
  isn't the summary language; the summary is a translated gist; an unknown language counts as the same) or
  `always`. Otherwise it shows its own title and text. Summaries that aren't needed stay in the library, just not
  shown, so switching back shows them again.
- `Story.summary` (`Summary`: title, text, language, the article IDs it covered) is current when it is in the
  summary language and covers exactly the story's articles (`isCurrent`). A new article in the story or a change of
  the summary language makes it out of date; it stays shown until the new one arrives. Stories that need a summary
  take their list title from it (`StoryList.allEntries(in:summaryLanguage:singleArticles:)`).
- Payload: `output_language`, `stories` (short id, articles oldest first: source, title, 1000-character excerpt);
  answer: `summaries` (story id, title, summary). 1–3 sentences, or 3–5 lines starting with "- " for stories with
  more than three articles. `SummaryStep.apply` stores answers for stories that still exist, ignores unknown IDs and
  empty answers.
- Topic translation (`TopicTranslation`): every `Topic` records its language; topics in another language (or none)
  are translated in one call (`assignModel`) – names and descriptions – and count as translated afterwards even if
  the answer left one out.

### Queues

- `AssignQueue` (main actor) derives its work from the library: pending articles are those without a story, unread
  or still in the attach window (`AssignQueue.pending`), so nothing is lost across restarts or crashes. It runs one
  batch at a time, newest first – the first batch of a run has 10 articles (first stories after ~10 s on a cold
  start, measured), later ones 20 – and each batch sees the stories of the previous one.
- Triggered after loading, after every refresh, after adding feeds and after AI settings change; a running queue
  picks up new articles by itself. A failing call is retried after 10 s and 60 s; after 3 attempts its articles are
  deferred until the next refresh (`trigger(retryingFailed: true)`). A setup error (`ClaudeError.isTransient ==
  false`, e.g. no claude) stops the run and shows "AI unavailable: …"; the next trigger looks for claude again.
- `SummaryQueue` (main actor) also derives its work from the library: unread stories needing a summary that isn't
  current (`SummaryStep.pending`: stories from several feeds first, then newer first). Up to 3 calls run at once,
  10 stories each, plus one topic translation when needed. Read stories wait until they are unread again ("+1
  new"), unless they are saved or have a saved article. Triggered with the assign queue and after every assign
  batch. A failing batch is retried after 30 s; a story whose summary failed 3 times (or was left out of 3 answers)
  waits for the next refresh and shows the error.
- `AICaller` makes every AI call of the queues: it finds claude (the path from the settings), runs the call, applies
  the answer and records it – `AIStatus` call list, `Library.usage`, the `ai` log. Usage is counted whenever claude
  actually ran (`ClaudeError.isTransient`), also when its answer was an error. The queues only add their retry
  policy.
- `PageSummaryQueue` (main actor) does P and T, only on request: `loadPage` stores the page text (through
  `LibraryHost.storePageText`) unless it is stored; `summarize` loads it if needed and writes the summary unless it
  is current. Requests are per article; one for an article already being worked on is ignored, except that T makes
  a running P go on to the summary. At most 2 run at once. Nothing is retried by itself (it is the user's action);
  errors stay in `AIStatus.pages` (the only record of the work) and show in the detail. `canSummarize` (also for the
  button) says whether T does anything; `pageOpened` (V in the window) forgets the stored text. AI off: T says so at
  once (`AIStatus.State.problem`: "AI is off (Settings → AI).") and P still works. `prepare` (Shift+S) is T that
  loads the page even with AI off and then fails with that message.
- `AIStatus`: `idle` / `off` / `organizing(count)` / `unavailable(reason)`, the stories being summarized and their
  errors, the pages being loaded or summarized (`PageWork`: phase, whether T asked for a summary) and their errors,
  for the status line ("Organizing 12 articles…", "Summarizing 5 stories…", "Summarizing page…", "AI
  unavailable: …"), and the last 20 calls (time, cost or error) for Settings → AI.
- AI settings (`Preferences`): `aiEnabled` (on by default), `claudePath` (empty = look it up), `assignModel` and
  `summaryModel` (free text, default `claude-haiku-5-5`), `aiEffort` (`low` / `medium` / `high`, default `low`); a
  change calls `onAIChange`, which triggers the queues. `summaryLanguage` (a language code, empty = the system
  language from `Locale.current`) is the language of story titles, topics and summaries; the prompt gets its English
  name (`OutputLanguage`). `singleArticleSummaries` (`never` / `otherLanguages` / `always`, default `never`) decides
  which single articles get a summary. Haiku was as accurate as Sonnet for assigning and 1.1–3× faster; for
  summaries it invented fewer facts than Sonnet in the lab.

### Page summary

- `Prompts.pageSummary` (tested in the lab on the pages of nine feeds): the payload has `output_language`, `source`
  (the feed), `title` (from the feed, so the AI can tell whether the page shows the article) and `page_text`. The
  answer has `status` (`ok` / `not_article`: a consent, subscription or login wall, an error page, another
  article), `tldr` (1–2 sentences) and `details` (3–7 points, only when they add facts).
- Details only for texts of `PageSummaryStep.detailsMinLength` (2 000) characters or more, decided in code: shorter
  texts get `pageSummaryTLDRSchema` without `details`. Even a stricter prompt didn't stop the model from repeating
  the TL;DR as points for a short news item.
- `summaryModel` (Haiku) with the usual effort, in `summaryLanguage`. Haiku took 1–9 s and $0.0004–0.003 per page;
  Sonnet cost 15–20× more and wasn't better.
- `PageSummaryStep.apply` stores an `ok` answer with a non-empty TL;DR (details trimmed, a stray "- " removed).
  `not_article` drops the stored page text, so the next T loads the page again, and shows "Open it with V, accept
  or log in, then press T again".

## Backup

- Backups go to iCloud Drive: `~/Library/Mobile Documents/com~apple~CloudDocs/Feedini/Backups/<Mac name>/`, one
  folder per Mac (`BackupStore.folderName` of the computer name), so a Mac thins out only its own backups and a
  restore can pick those of any Mac. The app isn't sandboxed, so it writes there like into any folder, without
  iCloud entitlements. macOS may ask once for access to iCloud Drive (it didn't for Feedini started with
  `make run`; a throwaway ad-hoc signed app got the prompt once, and a rebuild with the same bundle ID kept the
  grant); while such a prompt waits, so do file calls, so they never run on the main actor and the refresh loop
  doesn't await a backup.
- A backup is one file, `2026-11-03_14-30-15.feedinibackup` (local time, no spaces; `…_before-restore.feedinibackup`
  for the safety backup of a restore): zlib-compressed JSON with `format`, `version`, `created`, `device`, `app`,
  `settings` (`BackedUpSettings`) and `library`, the same object as `library.json`, so restoring reads it like
  loading does (a newer schema or format is refused). Page texts aren't in it (big, may show what the site knows about
  the user; P / T load them again); page summaries are. Settings of one Mac (the path to claude, collapsed folders,
  open at login) and the backup settings stay out.
- Nothing touches iCloud Drive until the user turns automatic backups on (off by default) or asks (Back Up Now,
  Restore…), so a possible access prompt comes then. Turning them on or changing the frequency checks at once; then
  after every refresh (also after start and wake). A backup is due after 90 % of the interval (`BackupPlan.isDue`; checks run every 5–60 minutes). The last
  backup is learned from this Mac's folder at the first check. A library without feeds isn't backed up (on a new Mac it
  would thin out the backups worth restoring). Backups run one at a time (`Backups.backUp`).
- Thinning out after each backup (`BackupPlan.expired`): every backup of the last 24 h, then the newest of every day
  for 14 days, the newest of every week for 8 weeks; the newest backup always stays.
- Restore (`RestoreSheet`; Settings → Backup, File → Restore from Backup…, the empty sidebar): the backups of all
  Macs, newest first and selected, those only in iCloud marked (a coordinated read downloads them), "Also restore
  settings" (on). Reading a backup shows a confirmation with what it holds (`BackupFile.Contents.summary`).
  `AppModel.restore` first backs up the current library (unless it has no feeds; if that fails nothing changes),
  stops the refresh loop and the AI queues, replaces the library (page texts stay for the articles it has), applies
  the settings if asked, lets the reader start over (`Reader.startOver`: selection All, no cursor, an empty ⌘Z history)
  and starts refreshing and organizing again. Restoring replaces, it never merges.
- Problems (`BackupError`: iCloud Drive off, no access, not a backup, newer version, other errors with their message)
  show in Settings → Backup and in the menu bar menu until a backup works.

## Storage and retention

- One file, `~/Library/Application Support/Feedini/library.json`: `{"version": 1, "library": {…}}`, pretty-printed
  with sorted keys and ISO 8601 dates, collections saved as arrays in a stable order (in memory they are
  dictionaries keyed by ID). `LibraryStore.schemaVersion` is bumped with every incompatible change, together with a
  migration in decoding `LibraryStore.File` (shared by loading and restoring a backup; only work on files, like
  moving the old page texts out, stays in `LibraryStore.load()`). Fields added later are optional when decoding (`usage`, `folders` and
  `removedFeeds` via `decodeIfPresent`; `Feed.folderID`, `Story.summary`, `Story.savedAt`, `Topic.language`,
  `Article.pageSummary`, `Article.savedAt` as optionals), so older files load without a bump. The version is read
  before the library, so a file from a newer Feedini isn't decoded for nothing.
- `LibraryStore` is an actor: `save(_:)` debounces (2 s from the first change, the latest library wins), writes are
  atomic, `flush()` writes a pending change at once (at quit). A file that can't be read – damaged, or saved by a
  newer Feedini – is moved aside as `library.unreadable-<unix time>.json`, never overwritten, and Feedini starts
  empty.
- An article belongs to a feed and is identified within it by `key` (guid / Atom id, else the link). `Article.date`
  is the published date clamped to the first sighting (future dates), or the first sighting without one.
- Page texts (P / T, up to `PageText.maxLength` each) are files of their own, `Feedini/pages/<article id>.txt`, so
  they are neither held in memory nor written again with every change of the library (J/K): `LibraryStore` writes
  one at once (`storePageText`) and reads it only when P shows it or T sends it (`pageText(for:)`); both run off the
  store actor and the main actor, so they don't wait for a library being written. The library only lists them
  (`Library.pageTextIDs`, `pageTexts` in the file); storing or forgetting one doesn't touch the articles, so the
  cached entries aren't rebuilt. A text the library no longer lists (V, `not_article`, a removed article –
  `Library.removeArticles`, used by `Retention` and `removeFeed`) is deleted once that library is written, except one
  stored meanwhile; loading deletes files the library doesn't list (a crash between the two writes) and forgets
  listed texts without a file (P loads the page again). A file without `pageTexts` is from before: its articles'
  `pageText` fields are moved into files when it is loaded, and the library is written without them at once.
- `Article.pageSummary` (T: TL;DR, details, language, date) is stored with the article and goes with it
  (`Retention`); a repeated T costs nothing.
- Measured with 5000 articles (a third read, 30 feeds, 2 KB of text each; `-O`): the file has 14 MB, encoding takes
  0.13 s (in the store actor, off the main actor), decoding 0.06 s; building all list entries 49 ms, filtering
  + rows + counts 2 ms, marking read + comparing the library 1 ms. Enough for "unread forever"; SQLite isn't needed.
  Reading only patches the cached entries (`StoryList.updateReadingState`), so J/K never rebuilds the list.
- `Retention.prune` (pure): unread articles stay forever. Read articles go once their story (or the article alone,
  without a story) has no article younger than `attachWindow` (72 h); each leaves a `Tombstone` (feed + key). A
  tombstone goes once it hasn't been seen in its feed for `tombstoneMargin` (3 days) before the feed's last
  successful download, so a feed that can't be downloaded keeps them. Topics without stories go too.
- Saving (`Article.savedAt`, `Story.savedAt`; `SavedItem`) keeps forever: a saved article, every article of a saved
  story, and a whole story with a saved article. Removing a feed keeps them too (`articleIDsKeptBySaving`), with the
  feed's name in `Library.removedFeeds` for their source labels (`sourceTitle(of:)`, also in the AI payloads).
  Articles of removed feeds that nothing saved keeps go at the next prune, without a tombstone, and so do the names
  of removed feeds no article comes from.

## Testing

- Swift Testing (`import Testing`, `@Test`, `#expect`). The test bundle is hosted by the app (`TEST_HOST`), so
  `@testable import Feedini` works. Under tests the `@main` entry point (`FeediniMain`) runs an empty `TestHostApp`
  instead of `FeediniApp` (`RuntimeEnvironment.isRunningTests`), so no window, refresh or menu bar item starts and
  the real app code needs no test guards.
- `claude` calls are tested through `FakeCommandRunner` and the envelope fixtures; `ProcessRunner` with real `/bin/sh`
  processes (stdin, large input, a command that doesn't read it, timeouts, grandchildren holding the pipe).
- Network code is tested through `StubURLProtocol` (`StubURLProtocol.session()`), never the real network. Every test
  uses unique hosts (`uniqueURL()`), so tests can run in parallel.
- The extraction script runs in a real hidden web view in the test host (`PageExtractor.extract(html:baseURL:)`
  with the `page-*.html` fixtures, a non-persistent data store and no settle delay; a `data:` URL for loading by
  address). Everything above it uses `FakePageExtractor`. The queues hold their host unowned, so a test that starts
  a page load waits for `pageQueue.waitUntilIdle()` before it ends.
- Checking the running app: `screencapture` needs the Screen Recording permission (without it: "could not create
  image from display"). Without it, inspect windows with `CGWindowListCopyWindowInfo` (owner `Feedini`).

### Test coverage

`make coverage` runs the tests and prints line coverage of the app target. Line-level detail:
`xcrun xccov view --archive --file <absolute path> build/Test.xcresult`.

Coverage is a tool for finding untested behaviour, not a goal. A test must assert observable behaviour (results,
state transitions, the commands that were run), not just execute lines. There is no global percentage target; the
total is dominated by the UI layer, which is deliberately not unit-tested.

Aim for ~100 % in the pure types: `Model/`, `Store/`, `Feeds/`, `Refresh/` (the scheduler with `ManualSleeper`),
`Backup/` (`BackupStore.temporary()`: a temporary folder standing in for iCloud Drive, UTC names),
`AI/` (the queues with `FakeCommandRunner`, `TestLibraryHost`, `FakePageExtractor` and `ManualSleeper` for the
backoff), `Debug/`, `KeyboardNavigation`, `ShortcutHelp`, `RelativeTime`, `Preferences`, and `Reader` (tested with a
real `AppModel` over a temporary store). In `PageExtractor` the WebKit callbacks for HTTP errors and failed loads
stay uncovered (they need the network).

Fine to leave uncovered: `App/` (`FeediniMain`, `FeediniApp`, `AppDelegate`, `LoginItem`, `AppModel.start` and the
non-test branch of `RuntimeEnvironment`) and `UI/` views. Keep these files pure wiring: logic that needs a test
moves into a testable type. Do not add abstractions to production code just to cover lines.

Tests that wait for real time are slow and flaky; timer-driven code takes an injected `sleep` instead. The queues
hold their `LibraryHost` unowned (the app's `AppModel` outlives them) – keep the test host in a local.

## Logs

`os.Logger` subsystem `cz.jsyrovy.feedini`, categories `refresh`, `feeds`, `ai` (one line per call with the metrics
of the answer), `store` and `backup`. Watch with
`/usr/bin/log stream --level info --predicate 'subsystem == "cz.jsyrovy.feedini"'` – in zsh, plain `log` is a shell
builtin. The test host is also called Feedini; filter by `processID` to see only the running app.
