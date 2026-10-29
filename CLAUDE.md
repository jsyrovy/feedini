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
- The app icon (`Feedini/AppIcon.icon`, Icon Composer format) is a placeholder: the 🎩 emoji on a purple gradient.
  The menu bar item shows the same emoji.
- Nothing may be installed on the dev machine (no XcodeGen, SwiftLint, xcbeautify, …). Formatting is `swift-format`
  from the toolchain, configured in `.swift-format` (4 spaces, 120 columns).

## Structure

```
Feedini/
  App/        @main entry (FeediniMain → FeediniApp with the main Window, Settings and MenuBarExtra, or an empty
              TestHostApp under tests), AppDelegate (owns the model, saves at quit), AppModel (library on the main
              actor, saving, refreshing), Preferences (UserDefaults), RuntimeEnvironment, Log (os.Logger categories)
  Model/      Feed, Article, Story, Topic, Tombstone (Codable, Sendable), Library (all of them, read state, removing
              feeds), StoryList (pure: entries, filtering by the sidebar selection, unread counts), ReadRules (pure:
              what visiting a row and M do; ListRow)
  Store/      LibraryStore (versioned JSON file, debounced atomic saving), Retention (pure: what is forgotten when)
  Feeds/      FeedFetcher (URLSession, concurrent, timeouts, ETag / Last-Modified), FeedParser (XMLParser: RSS
              0.9x / 1.0 / 2.0, Atom), HTMLText (HTML → plain text, excerpts), FeedLanguage (<language> or
              NLLanguageRecognizer), OPML (import / export)
  Refresh/    RefreshCoordinator (download + parse off the main actor), FeedMerge (pure: new articles, dedupe against
              known articles and tombstones), RefreshScheduler (periodic loop with an injected sleep)
  Support/    OneShotSignal (an awaitable one-time event)
  UI/         MainWindow (NavigationSplitView), Sidebar, StoryListView (keys, status bar), StoryRow / ArticleRow,
              DetailView (StoryDetail, ArticleDetail, SourcePage), WebPageView (WKWebView), Reader (window state:
              selection, cursor, expanded stories, kept entries, the shown page), KeyboardNavigation (pure: what a
              key does), RelativeTime, SettingsView, MenuBarContent
FeediniTests/ Swift Testing tests, mirroring the app folders
  Fixtures/   feeds with made-up text but the structure of real ones (RSS 0.91 / 1.0 / 2.0, Atom, long HTML,
              content:encoded, CDATA, HTML entities, windows-1250, duplicates, missing dates), a web page, an OPML file
  Support/    Fixture loader, ManualSleeper, StubURLProtocol (canned HTTP replies by URL), model stubs (`referenceDate`, `Article.stub`, …)
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
- Data comes only from the feeds. Neither the app nor the AI downloads web pages, except the source page the user
  explicitly opens (and that page never goes to the AI).
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
- Summaries only where they add something: stories with several articles, or articles in another language than the
  summary language (then it is a translation). A single article in the summary language shows its own excerpt.
- After closing the window the app keeps running in the menu bar (`.accessory`) and keeps refreshing, so opening it
  shows everything processed. With the window open it is a regular app with a Dock icon.

## Reading model

Three columns: sidebar (All, topics by unread count, feeds), story list (newest first), detail.

- A story with one article behaves like an article. A story with several articles has an AI title, a summary and
  source labels; its articles are collapsed in the list. An expanded story shows them indented below it, and J/K
  walks through them.
- Moving onto an item (click, arrows, J/K) marks it read. A collapsed story is marked read as a whole (the summary
  covered all its articles); in an expanded story articles are marked one by one, and the story is read when all
  its articles are. M toggles read / unread (on a collapsed story: all its articles).
- A read item doesn't vanish from the current list (no jumping under the cursor); it goes away when the sidebar
  selection changes or on refresh.
- The detail shows the text from the feed. V / Enter opens the source page the default way, Shift+V / Shift+Enter
  the other way (Settings → General: "Feedini window" (default) or "Default browser"). On a collapsed story with
  several articles V / Enter expands it (there is no single source page) and Shift+V / Shift+Enter does nothing.
- In the window the page replaces the feed text in the detail; V / Enter again or Esc returns to the feed text.

| Key | Action |
|---|---|
| J / ↓ | next item (story; article inside an expanded story) |
| K / ↑ | previous item |
| L / → | expand the story |
| H / ← / Esc | collapse the story (from an article: jump to its story) |
| V / Enter | open the source page the default way |
| Shift+V / Shift+Enter | open the source page the other way |
| M | toggle read / unread |
| R | refresh now |
| Shift+A | mark everything in the current selection (All, topic, feed) as read |
| ⌘, | settings |

Keys work in the list. While the web page has focus, only Esc works (it returns focus to the list).

Implementation:

- `StoryList.allEntries` turns the library into `StoryEntry`s: every story, plus every article no story holds yet
  (`.loose`, shown like a one-article story), newest first by their newest article. A one-article story uses the
  article's title. `entries(_:matching:keeping:)` filters by the sidebar selection (a feed shows every story with an
  article of it) and hides read entries unless they are in `keeping`. Counts match what is shown.
- `Reader` (main actor, UI state) keeps the cursor (`ListRow`: a story or an article of an expanded story). Moving
  onto a row (`visit`) applies `ReadRules` and adds the entry to `kept`, so it stays until the sidebar selection
  changes or a refresh ends (then only the entry under the cursor stays). Shift+A doesn't keep anything: the list
  empties. M keeps the entry too.
- `KeyboardNavigation.action` decides what a key does from the cursor, the rows, the expanded stories, the default
  way of opening pages and the shown page; `Reader.handle` carries it out. The story list's `onKeyPress` maps keys
  (plain keys only – with ⌘ / ⌃ / ⌥ they go to the menus). A double click opens like V / Enter.
- The source page (`WebPageView`): a `WKWebView` with the default persistent website data store (logins and cookies
  work), JavaScript on, no script message handlers. Link clicks and new windows open in the default browser. Esc in
  the page (`EscapableWebView`) returns to the feed text and focuses the list (`Reader.listFocusRequests`).
- `AppModel` holds the `Library`; every change goes through `update(_:)`, which hands a copy to `LibraryStore.save`
  in order. `entries` is cached until the library changes.

## Feeds

- `FeedFetcher` downloads with an ephemeral `URLSession` without a cache (20 s per request, 60 s per resource,
  `User-Agent: Feedini/…`), sends `If-None-Match` / `If-Modified-Since` from the previous download (304 →
  `notModified`) and ignores the `Content-Type` (some feeds are served as `text/html`). `fetchAll` runs 6 downloads
  at a time; every feed gets its own outcome, so one failing feed never affects the others. Failures are
  `FetchError`s with a message for the user – an ATS block (a redirect from HTTPS to HTTP) says so instead of a
  generic network error.
- `FeedParser` reads RSS 0.9x / 2.0 (no namespace), RSS 1.0 (RDF) and Atom with `XMLParser` and namespace
  processing; the root element decides the format, anything else (a web page) is `FeedParserError.notAFeed`. The
  encoding comes from the XML declaration (libxml2), never from the HTTP header.
- Feeds that aren't well-formed are repaired on the byte level and parsed again (`FeedParser.repairXML`): whitespace
  before the declaration, HTML named entities (`&nbsp;` → `&#160;`) and bare `&`. A feed broken in the middle keeps
  the items read up to there.
- An item's key is the guid / Atom id, else its link, else its title; items without any are dropped, duplicate keys
  keep the first. The title falls back to the start of the text. Dates: `pubDate` (RFC 822 variants), `dc:date`,
  Atom `published`, else `updated`. Author: `dc:creator`, the name in RSS `author` (`mail (Name)`), Atom
  `author/name`. Links are resolved against the feed URL; only `http(s)` links are kept.
- Text: `content:encoded` / Atom `content` when present, else `description` / `summary`, converted by
  `HTMLText.plainText` (paragraphs as blank lines, `<br><br>` too, list items with "• ", scripts, styles and
  comments dropped, entities decoded) and cut to `FeedParser.maxTextLength` (10 000 characters, ending in "…").
- `OPML.parse` returns every outline with an `xmlUrl` (any case), nested ones (categories) included, without
  duplicates, URLs as written – checking them is the importer's job. `OPML.export` writes OPML 2.0.
- `FeedLanguage`: the feed's `<language>` / `dc:language` / Atom `xml:lang` reduced to the primary code (`cs-CZ` →
  `cs`); without one, `NLLanguageRecognizer` on the title and the start of the text (at least 50 % sure).

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

## Storage and retention

- One file, `~/Library/Application Support/Feedini/library.json`: `{"version": 1, "library": {…}}`, pretty-printed
  with sorted keys and ISO 8601 dates, collections saved as arrays in a stable order (in memory they are
  dictionaries keyed by ID). `LibraryStore.schemaVersion` is bumped with every incompatible change, together with a
  migration in `LibraryStore.load()`.
- `LibraryStore` is an actor: `save(_:)` debounces (2 s from the first change, the latest library wins), writes are
  atomic, `flush()` writes a pending change at once (at quit). A file that can't be read – damaged, or saved by a
  newer Feedini – is moved aside as `library.unreadable-<unix time>.json`, never overwritten, and Feedini starts
  empty.
- An article belongs to a feed and is identified within it by `key` (guid / Atom id, else the link). `Article.date`
  is the published date clamped to the first sighting (future dates), or the first sighting without one.
- `Retention.prune` (pure): unread articles stay forever. Read articles go once their story (or the article alone,
  without a story) has no article younger than `attachWindow` (72 h); each leaves a `Tombstone` (feed + key). A
  tombstone goes once it hasn't been seen in its feed for `tombstoneMargin` (3 days) before the feed's last
  successful download, so a feed that can't be downloaded keeps them. Topics without stories go too.

## Testing

- Swift Testing (`import Testing`, `@Test`, `#expect`). The test bundle is hosted by the app (`TEST_HOST`), so
  `@testable import Feedini` works. Under tests the `@main` entry point (`FeediniMain`) runs an empty `TestHostApp`
  instead of `FeediniApp` (`RuntimeEnvironment.isRunningTests`), so no window, refresh or menu bar item starts and
  the real app code needs no test guards.
- Network code is tested through `StubURLProtocol` (`StubURLProtocol.session()`), never the real network. Every test
  uses unique hosts (`uniqueURL()`), so tests can run in parallel.
- Checking the running app: `screencapture` needs the Screen Recording permission (without it: "could not create
  image from display"). Without it, inspect windows with `CGWindowListCopyWindowInfo` (owner `Feedini`).

### Test coverage

`make coverage` runs the tests and prints line coverage of the app target. Line-level detail:
`xcrun xccov view --archive --file <absolute path> build/Test.xcresult`.

Coverage is a tool for finding untested behaviour, not a goal. A test must assert observable behaviour (results,
state transitions, the commands that were run), not just execute lines. There is no global percentage target; the
total is dominated by the UI layer, which is deliberately not unit-tested.

Aim for ~100 % in the pure types: `Model/`, `Store/`, `Feeds/`, `Refresh/` (the scheduler with `ManualSleeper`),
`KeyboardNavigation`, `RelativeTime`, `Preferences`, and `Reader` (tested with a real `AppModel` over a temporary
store).

Fine to leave uncovered: `App/` (`FeediniMain`, `FeediniApp`, `AppDelegate`, `AppModel.start` and the non-test
branch of `RuntimeEnvironment`) and `UI/` views. Keep these files pure wiring: logic that needs a test moves into a testable type. Do not add
abstractions to production code just to cover lines.

## Logs

`os.Logger` subsystem `cz.jsyrovy.feedini`. Watch with
`/usr/bin/log stream --level info --predicate 'subsystem == "cz.jsyrovy.feedini"'` – in zsh, plain `log` is a shell
builtin.
