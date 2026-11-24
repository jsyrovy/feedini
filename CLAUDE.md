# Feedini

Feedini is a native macOS RSS reader, driven by the keyboard, that groups articles from many feeds into stories and
topics and summarizes them with AI (through the local `claude` CLI). Without AI it is a plain, fast feed reader.
An iOS app (`FeediniMobile`, being built: see `plan/IOS_SYNC.md` locally) shares the core in `Shared/`; it is a plain
reader without AI that will show what the Mac produced through iCloud sync.

## Commands

```bash
make build    # xcodebuild Debug build into build/DerivedData
make build-ios # the iOS app for the simulator (unsigned)
make run-ios  # build-ios, then install and launch it in the simulator SIMULATOR (default "iPhone 17"); ARGS=-sampleLibrary
make run-device # the iOS app signed with the team on the iPhone DEVICE (UDID; default the only paired one); ARGS
make test     # Swift Testing unit tests (hosted by the app)
make coverage # tests + line coverage report of the app target (result bundle build/Test.xcresult)
make run      # build, kill a running instance, open the app
make install  # Release build into ~/Applications (INSTALL_DIR=…), restart it; make uninstall removes it
make release  # signed, notarized zip in build/release from a commit tagged v<version> (see "Releasing")
make publish  # that zip as a draft GitHub release of the pushed tag
make format   # xcrun swift-format, in place
make lint     # xcrun swift-format lint --strict
make clean    # rm -rf build
```

Run `make lint test` after every change. `CONFIG=Release make build` builds Release.

CI (`.github/workflows/ci.yml`, GitHub Actions on pushes to `main` and pull requests) runs `make lint`,
`make coverage`, `CONFIG=Release make build` and `make build-ios` in one job, with `SIGNING=none` (no team
signing there: ad hoc, without entitlements); the steps run even after an earlier one fails, and the result bundle is
uploaded when something fails. It uses the `xcode-27` runner image (a preview; `macos-26` only has
Xcode 26). `.github/workflows/homebrew.yml` updates the Homebrew cask when a release is published (see "Releasing").

## Toolchain and project

- Xcode 27 / Swift 6.4, deployment target macOS 15 and iOS 18 (iPhone only, portrait), Swift 6 language mode
  (complete strict concurrency).
- `Feedini.xcodeproj` is hand-written (`objectVersion = 77`) with file-system synchronized root groups for `Shared/`,
  `Feedini/`, `FeediniMobile/` and `FeediniTests/`: new files are picked up automatically, do not add file
  references to `project.pbxproj`. Edit the pbxproj only for build settings / targets; keep object IDs in the `FEED…`
  scheme.
- Targets: `Feedini` (the Mac app: `Shared/` + `Feedini/`), `FeediniMobile` (the iOS app, product and home screen
  name "Feedini": `Shared/` + `FeediniMobile/`) and `FeediniTests` (hosted by the Mac app). Shared code is compiled
  into both apps (no module, no `public`); it must not import AppKit or use Mac-only types – `make build-ios` checks.
  Code only the Mac runs (AI, backups, updates, keys) stays in `Feedini/`.
- Shared schemes `Feedini` (`xcshareddata/xcschemes/Feedini.xcscheme`; it collects coverage for the app target
  only) and `FeediniMobile` (no tests: the shared code is tested on the Mac).
- Bundle ID `cz.jsyrovy.feedini`, a regular app (`LSUIElement = NO`), generated Info.plist, App Sandbox off (the app
  runs the `claude` CLI, which a sandboxed app can't). App Transport Security keeps its defaults (no exceptions):
  only HTTPS feeds work.
- Signing: both apps are signed with the team `DZ7S6R9RRN` (automatic, "Apple Development"; the Makefile passes
  `-allowProvisioningUpdates`, so Xcode makes the development profiles with its account), which CloudKit needs;
  `make release` signs with Developer ID and its profile. `SIGNING=none make …` (CI) signs ad hoc without
  entitlements and builds the iOS app without sync (no `CLOUDKIT` condition); the Mac app then says "Sync isn't
  available in this build" (`SyncAvailability`). The test target stays ad hoc (no hardened runtime in Debug, so the
  team-signed host loads it). Hardened runtime is on in Release only (see "Releasing").
- Entitlements (`Config/`, outside the synchronized folders so they aren't copied into the bundle):
  `Feedini.entitlements` (`com.apple.developer.icloud-services` CloudKit, the container `iCloud.cz.jsyrovy.feedini`,
  `com.apple.developer.aps-environment`, `com.apple.developer.icloud-container-environment`) and
  `FeediniMobile.entitlements` (the same with `aps-environment`). The environments are build settings:
  `FEEDINI_CLOUDKIT_ENVIRONMENT` Development in Debug, Production in Release (so `make install`, `make release` and
  TestFlight share the data, and a Debug Mac syncs only with a Debug iPhone from Xcode), `FEEDINI_APS_ENVIRONMENT`
  development (`release.sh` sets production). The iOS app has the background mode `remote-notification`.
- Version: `MARKETING_VERSION` (`major.minor`) of the app targets, the same in Debug and Release and in both apps;
  the test target has none. `CURRENT_PROJECT_VERSION` stays 1; a release sets the build number.
- Commit: `make` passes `FEEDINI_COMMIT` (the short hash, `-dirty` with uncommitted changes; `release.sh` its own
  from the clean tree); `Config/Info.plist`, merged into the generated Info.plist of both apps, puts it under
  `FeediniCommit`. `RuntimeEnvironment.versionDescription` ("0.4 (4ceb8b3)") shows it in Settings → Version (iOS;
  the Mac above the update check), the `store` log at start and the Mac's About panel instead of the build number. A
  build from Xcode has none.
- The app icon (`Shared/AppIcon.icon`, Icon Composer format, both apps; for iOS 18 Xcode adds bitmaps) is a pixel-art top hat (32 × 32 grid) with the RSS
  symbol cut out of its crown: a black hat on cream in the light appearance, a cream hat on charcoal in the dark one
  (`fill-specializations`, `image-name-specializations`). Layers: outline, brim, band, crown, without glass (it
  blurs the pixels). The menu bar item shows the same hat, 16 × 16 pixels without the RSS symbol, as a template
  image (`Assets.xcassets/MenuBarIcon`, @1x and @2x).
- Nothing may be installed on the dev machine (no XcodeGen, SwiftLint, xcbeautify, …). Formatting is `swift-format`
  from the toolchain, configured in `.swift-format` (4 spaces, 120 columns).

## Structure

```
Shared/       compiled into both apps
  App/        AppModel (library on the main actor, saving, refreshing, feeds, folders, saved links, source pages,
              the cached entries; PlatformServices: what the Mac adds), LibraryHost (what the page loader and the AI
              queues change the library through), Preferences (the shared ones, UserDefaults), RuntimeEnvironment
              (tests, the version and commit), Log (os.Logger categories)
  Model/      Feed, Article, Story (+ Summary), Topic, Tombstone (Codable, Sendable), Library (all of them, read
              state, removing feeds), Folder (+ Library's folder operations, SidebarDrag: dragging feeds and
              folders), Saved (Library's saving of articles, names of removed feeds), SavedLink (pages saved by
              their address: comparing addresses, Library.saveLink), AIUsage (AIUsageDay: AI calls per day),
              StoryList (pure: entries, filtering by the sidebar selection, Saved, unread counts, ListOrder),
              ReadRules (pure: what visiting a row and M do; ListRow, the rows of the list), UndoHistory (pure:
              ReadingState, the steps of undo)
  Store/      LibraryStore (versioned JSON file, debounced atomic saving, page texts as files of their own),
              Retention (pure: what is forgotten when)
  Feeds/      FeedFetcher (URLSession, concurrent, timeouts, ETag / Last-Modified), FeedParser (XMLParser: RSS
              0.9x / 1.0 / 2.0, Atom), HTMLText (HTML → plain text, excerpts), FeedLanguage (<language> or
              NLLanguageRecognizer), OPML (import / export), FeedSubscriber (checks an address or OPML entries before
              adding: HTTPS only, a real feed, not subscribed yet), PageExtractor (a source page's text in a hidden
              WKWebView: PageScript, PageText, PageExtracting), PageMetadata (+ PageContent: what a page says about
              itself)
  Refresh/    RefreshCoordinator (download + parse off the main actor), FeedMerge (pure: new articles, dedupe against
              known articles and tombstones), RefreshScheduler (periodic loop with an injected sleep)
  Pages/      PageLoader (P and Save Link on request: loading and storing page texts, at most 2 at a time; goes on to
              a summary through PageSummarizing on the Mac), PageStatus (@Observable: the pages being loaded or
              summarized and their errors)
  Reading/    ReadingSession (@Observable window state: selection, cursor, expanded stories, articles read while the
              list is shown, the undo history; visiting, M, S, Shift+A, undo)
  Summaries/  SummaryStep (what the list needs: needsSummary, isCurrent) + SingleArticleSummaries, SummarySettings
              (the summary language and choice the list shows, in the library), OutputLanguage (names, choices)
  Sync/       iCloud sync: CloudSyncEngine (the CKSyncEngine wrapper), SyncController (the state, sending, applying, conflicts; SyncStatus, SyncEngining),
              SyncRecord (+ Library: the records of the library's parts as fields,
              names, encrypted fields), SyncChanges (pure: the records two libraries differ in), SyncMerge (pure:
              applying fetched records and deletions, conflicts, merging libraries), SyncStateStore (SyncState:
              sync.state), SyncSwitch (on / off as the platform's setting says), SyncSchema (the zone's version)
  Support/    OneShotSignal (an awaitable one-time event), ConcurrentMap (`concurrentMap(limit:)`, order kept),
              RelativeTime ("5m", "3h", then the date)
  UI/         SwiftUI views of both apps: Removal (confirming the removal of feeds or a folder), FolderViews
              (FolderNameSheet, MoveToFolderMenu, FolderPicker), ListOrderPicker, TextViews (Paragraphs, SummaryText,
              PageLoadStatus, PageTextBody, SummaryBox, PageSummaryText, SavedLinkLabel, `Library.byline`),
              ImportReport (importing an OPML file and what it did, SkippedFeedRow)
  Debug/      Debug builds only: SampleLibrary (made-up library for `-sampleLibrary` on iOS)
  AppIcon.icon
Feedini/      the Mac app
  App/        @main entry (FeediniMain → FeediniApp with the main Window, Settings and MenuBarExtra, or an empty
              TestHostApp under tests), AppDelegate (owns the services, saves at quit, Dock icon only with the window,
              refresh after wake), MacServices (owns the AppModel: the AI queues, backups and restoring, the update
              check, sync), MacPreferences (the Mac's preferences on top of the shared ones: menu bar, AI, backups,
              updates, sync), SyncAvailability (the CloudKit entitlement, the iCloud account), LoginItem
              (SMAppService)
  AI/         ClaudeLocator (binary lookup), ProcessRunner (subprocess with stdin, timeout, process group),
              ClaudeClient (CLI arguments, envelope, errors), Prompts (system prompts + JSON schemas), AssignStep
              (payload with short IDs), Validation (pure: applying an assign answer), SummaryStep (pure: which
              stories, priority, payload, applying) + TopicTranslation, AIQueue (AICaller: one call with its
              recording; AssignQueue: serial batches, backoff; SummaryQueue: parallel batches, priority;
              AIConfiguration), AIUsageRecording (Library.recordAICall), PageSummaryStep (pure: page summary
              request, applying), PageSummaryQueue (T / Shift+S on request: summarizing pages on top of the
              PageLoader), AIStatus (@Observable state, stories being summarized, recent calls)
  Backup/     BackupFile (pure: the file format, names, compression; BackupError), BackupPlan (pure: when a backup
              is due, thinning out; BackupFrequency), BackupStore (the files in iCloud Drive, file coordination),
              Backups (@Observable: automatic backups, Back Up Now, reading backups), BackedUpSettings (the settings
              in a backup, `MacPreferences.apply`)
  Updates/    AppVersion (pure: parsing, comparison), LatestRelease (UpdateError, GitHub's latest release: request,
              parsing, fetch), UpdateChecker (@Observable: check now, daily loop), HomebrewCask (is it installed, the
              `brew upgrade` command)
  Debug/      Debug builds only (`#if DEBUG`): DebugCommands (the Debug menu: reorganize all as a cold start,
              rewrite summaries, add made-up articles to a "Debug" feed)
  UI/         MainWindow (NavigationSplitView), Sidebar (+ folders, dragging), StoryListView (keys, status bar),
              StoryRow / ArticleRow,
              DetailView (StoryDetail, ArticleDetail + PagePreview + PageButtons + SaveButton, SourcePage), SummaryView (+
              PageSummaryView), WebPageView (WKWebView), Reader (the main window on top of its
              ReadingSession: keys, the shown page or page text, the sheets, focus), UndoCommands (Edit →
              Undo / Redo), KeyboardNavigation (pure: what a key does),
              ShortcutHelp (pure: the shortcuts by group) + ShortcutsView (the ? sheet), SettingsView
              (tabs) + FeedsSettings + GeneralSettings (+ UpdateSettings) + AISettings + SyncSettings + BackupSettings, RestoreSheet, BackupCommands
              (File menu), SaveLinkSheet (+ SaveLinkButton), MenuBarContent (+ MenuBarLabel)
FeediniMobile/ the iOS app
  App/        FeediniMobileApp (@main: the AppModel without AI, a ReadingSession, refreshing only in the foreground,
              every 5 minutes without a setting, the sample library in Debug), MobileSync (sync on by default, its setting)
  UI/         RootView (NavigationStack: Route, `-screen` in Debug), SidebarScreen, StoryListScreen (+ EntryRow,
              swipe actions, Mark All as Read), EntryDetailScreen (StoryDetail, ArticleDetail: feed text, page text
              or web page switched in the navigation bar, Reload Page, SafariView), WebPageView (WKWebView),
              SaveLinkSheet (PasteButton), SettingsScreen (+ FeedsScreen: adding,
              removing, folders, OPML import and export)
FeediniTests/ Swift Testing tests of the shared code and the Mac app, in folders named like theirs
  Fixtures/   claude CLI envelopes (success, is_error, no structured_output, wrong shape; anonymized IDs), feeds
              with made-up text but the structure of real ones (RSS 0.91 / 1.0 / 2.0, Atom, long HTML,
              content:encoded, CDATA, HTML entities, windows-1250, duplicates, missing dates), a web page, an OPML
              file, article pages with made-up text for the extraction (`page-*.html`: a cookie consent overlay, an
              article in divs, `main` with a menu and navigation, JSON-LD only, no article, meta tags)
  Support/    Fixture loader, ManualSleeper, StubURLProtocol (canned HTTP replies by URL), FakeCommandRunner
              (canned CLI replies, recorded calls), FakePageExtractor (canned page texts and metadata, recorded
              requests), TestLibraryHost + `ClaudeLocator.stub` + `MacServices.test()` (fake claude and pages) +
              `AppModel.test()` (the shared model alone, as on iOS), model
              stubs (`referenceDate`, `Article.stub`, …)
Config/       entitlements of both apps, Info.plist (the commit, merged into the generated ones)
scripts/      release.sh (`make release`) and publish.sh (`make publish`), see "Releasing"
CHANGELOG.md  one section per released version
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
  source page opened with V, its text for P (preview) and T (summary), a page saved with Save Link…, or – chosen in
  Settings ("Show articles as": Page text / Web page; the feed text is the default) – the page of every article the
  user moves onto. Only T (and Shift+S / Save Link… with AI, which prepare it) sends a page's text to the AI.
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
  about the same event joins the known story, which comes back as unread showing only the new article.
- A story card shows only what is new: its unread articles, plus those read while the list is shown. Its title,
  summary, sources and article count follow them, and with one article left it behaves like an article. The
  summary is written from the unread articles only.
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
  P shows the text of the source page instead, T a TL;DR of it; both only on request, on a single article. Settings
  → General can make the page text or the web page what an article shows (see "Reading model").
- After closing the window the app keeps running in the menu bar (`.accessory`) and keeps refreshing, so opening it
  shows everything processed. With the window open it is a regular app with a Dock icon.
- Folders ("Folders" in the UI, not "categories", which would blur with the AI topics) group feeds by hand: one
  level, a feed in at most one folder, folders in the user's order. They don't reach the AI.

## Reading model

Three columns: sidebar (All, Saved, topics by unread count, folders with their feeds, feeds in no folder), story
list (newest first), detail.

- A story shows only its visible articles: the unread ones and those read while the list is shown (until the sidebar
  selection changes or a requested refresh ends, see "Refresh"). Read articles show neither in the list nor in the detail. Everything on the
  card and in the detail comes from the visible articles: the title, the number of articles, the sources, the
  accent bar, expanding, the keys. A story with one visible article behaves like an article (V, P, T, S, no
  expanding). A story with several has an AI title, a summary and source labels; its articles are collapsed in the
  list. An expanded story shows them indented below it, and J/K walks through them.
- Moving onto an item (click, arrows, J/K) marks it read. A collapsed story is marked read as a whole (the summary
  covered all its visible articles); in an expanded story articles are marked one by one, and the story is read when
  all its articles are. M toggles read / unread (on a collapsed story: all its visible articles).
- The list is newest first; View → Sort or the toolbar's sort menu turns it to oldest first (`Preferences.listOrder`,
  remembered across launches, not in backups). It reverses the whole list, Saved (by save date) too; the articles
  inside a story stay newest first. The cursor stays on its row.
- A read item doesn't vanish from the current list (no jumping under the cursor); it goes away when the sidebar
  selection changes or on a requested refresh (not a scheduled one). So does a read article from its story card, except in the entry under the
  cursor, where nothing changes.
- A story is in a feed (or folder) only with a visible article of it; the unread counts count stories with unread
  articles, in the feeds and folders of those articles.
- S saves the article under the cursor for later, S again removes it from Saved. Only articles are saved: an
  article row, a story with one article or a loose article; on the row of a story with several articles S does
  nothing (like P, T and Shift+V). Saved articles have a bookmark in every list, and so does the row of a story with
  a saved article. The detail of an article has a Save / Saved toggle doing what S does (`SaveButton`, also without a
  link), and a story's detail marks its saved articles.
- Saved (in the sidebar under All, with the number of saved articles, not in the menu bar count) shows every saved
  article, read or not, most recently saved first: saving happens on items that moving onto them already read. A
  saved article is shown on its own, as itself: its title, the feed text, the TL;DR of its page – never the title or
  summary of its story. An article removed from Saved stays in its place until the selection changes or a refresh;
  Shift+A does nothing there. Saved articles are never forgotten, but they don't keep their story (see "Storage and
  retention"), and removing a feed keeps its saved articles.
- Save Link… (the + next to Refresh in the toolbar, File → Save Link… ⌘L, the menu bar menu, or a link dropped on the
  list or on Saved) saves a web page by its address, like Pocket: `SaveLinkSheet` offers an `http(s)://` address from
  the clipboard, closes at once, and says so when the page is in Saved already (it doesn't move the cursor there:
  that would read it). The page is loaded in the background like Shift+S: its text, and with AI a TL;DR. A saved
  link is an article of no feed (`SavedLink`), only in Saved – not in All, the unread counts or the AI's stories –,
  unread until moved onto. Its row has a link icon and the site's name, its detail "Saved link, added …", a
  "Reload Page" button and the page's text instead of the feed text (P loads the page again; V doesn't forget the
  text). The address of an article that is there already (from a feed, `SavedLink.key`) saves that article instead.
  S removes it from Saved, and it goes at the next refresh (⌘Z brings it back until then). Adding isn't a ⌘Z step.
- The detail shows the text from the feed. V / Enter opens the source page the default way, Shift+V / Shift+Enter
  the other way (Settings → General: "Feedini window" (default) or "Default browser"). On a collapsed story with
  several articles V / Enter expands it (there is no single source page) and Shift+V / Shift+Enter does nothing.
- In the window the page replaces the feed text in the detail; V / Enter again or Esc returns to the feed text.
- What an article shows when the cursor moves onto it (click, J/K) is a setting (Settings → General, "Show articles
  as": `Preferences.articleView`): the feed text (default), the page text (as P) or the web page (as V in the window,
  always in the window, whatever V / Enter opens). The summary box shows above the feed and page text, not on the web
  page. It doesn't apply to a story with several articles (no single page) or an article without a link; a saved
  link shows its page text for Page text too. A page that isn't stored loads only once the cursor has stayed on the
  article for `Reader.settleDelay` (0.5 s), so J/K doesn't load every page it passes; the detail says "Loading page…"
  meanwhile (also after an earlier failure: moving onto the article tries again). P switches the preferred page text
  to the feed text and back; Esc and the key that opens pages in the window (V / Enter, or Shift+V / Shift+Enter with
  "Default browser") switch the preferred web page to the feed text, and that key opens the web page from the page
  text (as V, forgetting the text). A double click on the row never closes its page, it shows a waiting one at once
  (`Reader.openOnDoubleClick`). T never runs by itself. When undo moves the cursor onto the article it is on already
  (its row, or the story row the AI moved it to), the detail stays as the user left it (`Reader.cursorMoved`); on
  another article it shows the preferred view. The web page shown this way keeps the stored page text (only V forgets
  it), and it takes the keyboard focus only when clicked into (`EscapableWebView`: a refused focus goes back to the
  list), so J/K keep working. On iOS the setting (Settings → "Show Articles As") is what an opened article shows
  first, without a delay (a tap is an explicit request); a segmented switch in its navigation bar (feed text, page
  text, web page; a saved link has no feed text, an article without a link no switch;
  `Preferences.ArticleView.choices(for:)`) changes it. The web page is a `WKWebView` of the app (`WebPageView`, links
  open in the browser), not Safari's view; "Open Page" opens the page as "Open Pages In" says.
- P (preview) shows the text of the source page instead of the feed text (loaded the first time, then stored); P
  again returns to the feed text. A text cut at `PageText.maxLength` ends with a pointer to V. Works without AI. On a
  saved link (no feed text) P loads the page again instead, also from the source page in the window.
- T (TL;DR) summarizes the source page with AI: a box above the text with the TL;DR and, for longer texts, details
  as bullet points. It replaces the AI gist of the feed text of a one-article story (it is more complete). T on a
  current summary does nothing; after a change of the summary language it writes a new one from the stored text.
  From the source page in the window, T (or its "Summarize Page" button) returns to the text with the summary.
- Shift+S saves the article like S (never removes it) and, when it has a link, prepares its TL;DR in the
  background, as T would, without changing the detail: P and T are then instant, and the text stays even if the page
  goes away. Without AI the page text is still stored; on a story with several articles it does nothing. While it runs
  the row shows ✨, a failure (AI off, a consent or login wall, an error) ⚠︎ with the message, in every list; only T
  tries again.
- ⌘Z takes back reading and saving in the main window, one step at a time, ⇧⌘Z does it again (a new step clears
  that). A step is every change of reading or saving: moving onto an unread item, M, Shift+A (all of it at once), S,
  Shift+S (the saving; the page work goes on). It puts back exactly the state before, shows the item's row without
  reading it, keeps it in the list (an article made unread again shows in its story again) and doesn't change the sidebar selection. The menu names
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
| P | the text of the source page instead of the feed text, again: back (a saved link: load it again) |
| T | TL;DR of the source page (AI) |
| Shift+S | save the article for later and prepare the TL;DR of its source page |
| M | toggle read / unread |
| S | save the article for later / remove it from Saved |
| R | refresh now |
| Shift+A | mark everything in the current selection (All, topic, folder, feed; not Saved) as read |
| ? | keyboard shortcuts |
| ⌘Z / ⇧⌘Z | undo / redo the last reading or saving |
| ⌘, | settings |

Keys work in the list. While the web page has focus, only Esc works (it returns focus to the list).

Implementation:

- `StoryList.allEntries` turns the library into `StoryEntry`s: every story with all its articles, plus every article
  no story holds yet (`.loose`, shown like a one-article story), newest first by their newest article (also when
  that one is read and hidden). A story's entry keeps what it is built from (`StoryEntry.StoryInfo`: the story's
  title and stored summary, the summary language and choice), and `StoryEntry.show(_:)` derives the title, whether
  it needs a summary, the summary and whether it is current from the articles it shows: a one-article story uses
  the article's title. `StoryEntry.visible(keeping:)` narrows an entry to its unread articles and those in
  `keeping` (`nil` when none is left). `entries(_:matching:folders:keeping:)` narrows every entry, then filters by
  the sidebar selection (a feed shows every story with a visible article of it, a folder every story with a visible
  article of one of its feeds); `ordered(_:_:)` puts them in the chosen `ListOrder` (`ReadingSession.entries`). Counts
  match what is shown: a story counts once in a folder, even with unread articles of several of its feeds.
- `StoryList.savedEntries` builds Saved from the saved articles, each a `.savedArticle` entry of its own
  (`savedEntry(for:)`). `StoryEntry.singleArticle(at:)` says what S (and P, T, Shift+S) works on on a row,
  `containsSaved` whether the row has a bookmark. `AppModel` caches Saved with the other entries; reading and saving
  patch the entries (`StoryList.updateReadingState`) and saving rebuilds only Saved. `ReadingSession.unsaved` remembers the
  save dates of articles removed while Saved is shown, so they keep their place (`AppModel.savedEntries(keeping:)`;
  `entry(_:)` builds a `.savedArticle` entry on demand, saved or not).
- `ReadingSession` (shared, main actor, UI state) keeps the selection and the cursor (`ListRow`: a story or an
  article of an expanded story) and narrows every entry it gives out (`entry`, `entries`; Saved shows its articles
  read or not). The Mac's `Reader` owns one and adds the keys, the shown page and the sheets; a cursor move
  (`onCursorMove`) shows the preferred view instead of the shown page. Moving onto a
  row (`visit`) applies `ReadRules` and adds the articles it read to `keptArticles`, so they stay until the sidebar
  selection changes or a requested refresh ends (`AppModel.onRefresh`; then only the visible articles of the entry
  under the cursor stay). M keeps
  the articles it reads too, and so does showing the row of an undone step. Shift+A doesn't keep anything: the list
  empties.
- `KeyboardNavigation.action` decides what a key does from the cursor, the rows, the expanded stories, the default
  way of opening pages and the shown page; `Reader.handle` carries it out. The story list's `onKeyPress` maps keys
  (plain keys only – with ⌘ / ⌃ / ⌥ they go to the menus); ? is matched as a character, not a key, so it works on
  any keyboard layout. A mapped key is always used up, also when it does nothing: the list's type-to-select would
  otherwise move onto (and read) a row starting with that letter. A double click opens like V / Enter (but never
  closes a page shown in the window).
- `ReadingSession.recording` snapshots the `ReadingState` (read and save dates of the articles) before a change and records it in `UndoHistory` (its callers only make changes that change
  something); undo and redo are `Library.restore`, which returns the replaced state for the other stack
  (`AppModel.restore` patches the cached entries like reading and saving). `UndoCommands` replaces Edit → Undo / Redo: while the main
  window is key (`Reader.isMainWindowKey`, set by `AppDelegate` from the key window notifications) they go to the
  reader, otherwise `undo:` / `redo:` go to the responder chain.
- `ShortcutHelp.item(for:)` switches over every `ListKey` (`CaseIterable`), so a new key doesn't compile without
  its line in the help.
- `Reader.shown` is what the detail shows instead of the feed text: the source page (V) or its text (P), never both.
  Moving, a new sidebar selection and Shift+A set it to the preferred view (`showPreferredView`; `nil` without an
  article under the cursor). `Reader.waitingArticle` is the article whose page waits for the cursor to settle (an
  injected `sleep`, tested with a signal that ends every wait); a move, P, V or Esc cancel the wait, and only P / V
  call the `PageLoader` at once. The preferred web page doesn't call `pageOpened`.
- The source page (`WebPageView`): a `WKWebView` with the default persistent website data store (logins and cookies
  work), JavaScript on, no script message handlers. Link clicks and new windows open in the default browser. Esc in
  the page (`EscapableWebView`) returns to the feed text and focuses the list (`Reader.listFocusRequests`).
- When the AI puts a loose article into a story, the entry's ID changes (`.loose` → `.story`). `ReadingSession`
  follows it
  on every library change (`AppModel.onLibraryChange`): the cursor moves to the article inside the (expanded) story
  when the story shows several articles, else onto the story's row – nothing is marked read by that. Kept articles
  keep their IDs.
- Summaries in the detail (`SummaryView`): a story with several articles shows its summary between the title and
  the articles; a one-article story that needs one shows it above the feed text. Lines starting with "- "
  become bullet points. Without a summary yet: "Summarizing…" (or the error after repeated failures); an out-of-date
  one (an unread article it doesn't cover, another language) stays with "Updating summary…" while the AI works.
- AI in the list: a loose article shows ✨ while the AI organizes (`AIStatus.organizing`); the status bar shows
  "Organizing N articles…", "Summarizing N stories…", "Summarizing page…" or "AI unavailable: …" next to the
  refresh state. Stories showing articles of several feeds have an accent bar and source labels.
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
- `PageScript.metadata` reads what the page says about itself (`PageMetadata`): the title (`og:title`,
  `twitter:title`, JSON-LD `headline`, else `<title>` without the site's name at its end), the site (`og:site_name`,
  JSON-LD `publisher`), the author (`<meta name=author>`, JSON-LD; not a profile link) and the published date
  (`article:published_time`, JSON-LD `datePublished`, else the first `<time datetime>`; ISO 8601). Only saved links
  use it; their address stays as given (a page may redirect to its consent page).
- Measured on nine Czech and English feeds: 1.8–2.5 s per page; menus that the container's `innerText` kept are
  gone. A site that redirects to its consent page on the server (iDNES) gives the consent text until the user
  accepts it in the window (V); the AI then answers `not_article`.

## Running in the background

- Closing the main window doesn't quit (`applicationShouldTerminateAfterLastWindowClosed` is false): the model
  lives in `AppDelegate`, so refreshing, organizing and summarizing go on. With the window open Feedini is a
  regular app (Dock icon, menus); when it closes it switches to `.accessory` and only the menu bar item stays
  (`AppDelegate.mainWindowIsOpen`, called from `MainWindow` appearing and disappearing).
- Menu bar item (`MenuBarExtra`, menu style): the hat with the number of unread stories (optional), and a menu with
  the count, "Open Feedini" (⌘O), "Save Link…" (⌘L, opens the window with the sheet), "Refresh Now" (⌘R), the time of the last refresh, the AI status (always shown:
  "AI: ready", "AI: off", or what it is doing / why it can't run), a backup problem if there is one, "Feedini <version>
  Is Available…" (opens the release page) when the update check found one, Settings and Quit.
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
- **General** (`GeneralSettings`; `Preferences`, the menu bar and update check in `MacPreferences`): refresh interval (`refreshMinutes`: 5 / 15 / 30 / 60, default 15),
  where V / Enter opens pages (`pageOpening`: `window` (default) / `browser`), what an article shows (`articleView`:
  `feedText` (default) / `pageText` / `webPage`, with a note that the others load the page every time), open at login (`LoginItem`, the
  system's login items via `SMAppService.mainApp`; its state is read from the system, not stored) and the unread
  count in the menu bar (`showsUnreadCount`, on by default), and the update check (the running version, "Check for
  updates daily", "Check Now" and the result, see "Update check"). Values that aren't offered fall back to the default.
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

- `RefreshScheduler` (main actor) refreshes at start and then `interval` after each refresh finished (Mac: Settings →
  General, 5 / 15 / 30 / 60 min, default 15; iOS: a fixed 5 min, `FeediniMobileApp.refreshInterval`, no setting: it
  refreshes only while open), so refreshes never overlap. `refreshNow()` cuts the wait short and is ignored while a
  refresh runs; `setInterval(_:)` restarts the current wait with the new length. Tested with `ManualSleeper`.
- Every refresh has a `RefreshScheduler.Trigger`: `requested` for `start()` and `refreshNow()` (launch, the iOS app
  coming to the front, the Mac waking, R / Refresh / pull to refresh), `scheduled` after a wait. Only a requested
  refresh runs `Retention.prune` and drops the articles read while the list is shown (`AppModel.onRefresh`); a
  scheduled one only adds new articles, so the list doesn't change under the reader every few minutes. A refresh
  asked for while a scheduled one runs makes that one requested (`AppModel.refreshNow`).
- `RefreshCoordinator.refresh` (`@concurrent`) downloads all feeds (`FeedFetcher.fetchAll`) and parses them into
  `FeedRefresh` values (`updated` / `notModified` / `failed(message)`); `FeedMerge.merge` (pure) applies them to the
  library on the main actor and returns the new article IDs.
- Merging: items with a known key are left alone (no edits after the fact); items with a tombstone only refresh its
  `lastSeen`; the rest become unread articles with `firstSeen = now`. The first download of a feed (no
  `lastSuccess` yet, and no articles or tombstones of it in the library) turns items older than
  `FeedMerge.firstDownloadMaxAge` (7 days) into tombstones, so adding a feed with its whole history doesn't flood the
  list. A feed with articles or tombstones but no download of its own (it came from another device or a backup)
  isn't downloaded for the first time: tombstones made there would hide its unread articles elsewhere. A failed feed only records `lastError`.
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
  topic with that name. An article joining a read story makes the story unread again, showing only the new
  article. It returns metrics, which are logged.
- An article is "processed" once it belongs to a story; articles without one are shown on their own (`.loose`).

### Summary step

- A summary is written from a story's unread articles only. They need one when there are several; a single one
  needs one as `SingleArticleSummaries` says (`SummaryStep.needsSummary`): `never`, `otherLanguages` (the article's
  language isn't the summary language; the summary is a translated gist; an unknown language counts as the same) or
  `always`. Otherwise it shows its own title and text. Summaries that aren't needed stay in the library, just not
  shown, so switching back shows them again. In the list the articles a story shows decide (`StoryEntry.show(_:)`).
- `Story.summary` (`Summary`: title, text, language, the article IDs it covered) is current when it is in the
  summary language and covers every unread article of the story (`isCurrent`; it may cover more). Reading some of
  them doesn't make it out of date; a new unread article it doesn't cover or a change of the summary language does,
  and it stays shown until the new one arrives. A partly read story whose one remaining article needs a summary of
  its own (another language) therefore shows the older summary of several articles. Stories that need a summary
  take their list title from it.
- Payload: `output_language`, `stories` (short id, unread articles oldest first: source, title, 1000-character
  excerpt);
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
  10 stories each, plus one topic translation when needed. Read stories wait until they are unread again (a new
  article joins them), saved articles or not. Triggered with the assign queue and after every assign batch. A
  failing batch is retried after 30 s; a story whose summary failed 3 times (or was left out of 3 answers) waits for
  the next refresh and shows the error.
- `AICaller` makes every AI call of the queues: it finds claude (the path from the settings), runs the call, applies
  the answer and records it – `AIStatus` call list, `Library.usage`, the `ai` log. Usage is counted whenever claude
  actually ran (`ClaudeError.isTransient`), also when its answer was an error. The queues only add their retry
  policy.
- P and T run only on request. The shared `PageLoader` (main actor, owned by `AppModel`) does P: `loadPage` stores
  the page text (through `LibraryHost.storePageText`) unless it is stored. The Mac's `PageSummaryQueue` does T on
  top of it: `summarize` asks the loader (`enqueue(_:summary: true)`), which loads the text if needed and then
  calls the queue back (`PageSummarizing`) in the same slot; the summary is written unless it is current. Requests
  are per article; one for an article already being worked on is ignored, except that T makes a running P go on to
  the summary. At most 2 run at once. Nothing is retried by itself (it is the user's action); errors stay in
  `PageStatus` (`AppModel.pageStatus`, the only record of the work) and show in the detail. `canSummarize` (also for
  the button) says whether T does anything; `pageOpened` (V in the window) forgets the stored text. AI off: T says so at
  once (`AIStatus.State.problem`: "AI is off (Settings → AI).") and P still works. `prepare` (Shift+S) is T that
  loads the page even with AI off and then fails with that message.
- A saved link's page text is all it has: Save Link… without AI only loads it (`AppModel.saveLink` asks
  `PlatformServices.prepareSavedLink`, which declines without AI: no "AI is off" on every link), loading fills in its title, site, author and date (`Library.applyPageMetadata`), `pageOpened` and
  a `not_article` answer keep the text (`Library.forgetPageText`; the message points to P), and `reload` (P) loads
  the page again – the stored text and summary stay
  until the new text is stored, then a new summary is written when AI is on. The row shows ✨ / ⚠︎ for loading it too.
- `AIStatus`: `idle` / `off` / `organizing(count)` / `unavailable(reason)`, the stories being summarized and their
  errors, the page work (its `PageStatus`: `PageStatus.Work`: phase, whether T asked for a summary), for the status
  line ("Organizing 12 articles…", "Summarizing 5 stories…", "Summarizing page…", "AI
  unavailable: …"), and the last 20 calls (time, cost or error) for Settings → AI.
- AI settings (`MacPreferences`): `aiEnabled` (on by default), `claudePath` (empty = look it up), `assignModel` and
  `summaryModel` (free text, default `claude-haiku-5-5`), `aiEffort` (`low` / `medium` / `high`, default `low`); a
  change calls `onAIChange`, which triggers the queues (`MacServices`) and hands `summarySettings` to the model. `summaryLanguage` (a language code, empty = the system
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
  open at login) and the backup settings stay out; the others go in (also `articleView`; an optional field, so an older
  backup restores without it).
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
  `MacServices.restore` first backs up the current library (unless it has no feeds; if that fails nothing changes),
  stops the refresh loop and the AI queues, replaces the library (page texts stay for the articles it has), applies
  the settings if asked, lets the reader start over (`ReadingSession.startOver`: selection All, no cursor, an empty ⌘Z history)
  and starts refreshing and organizing again. Restoring replaces, it never merges.
- Problems (`BackupError`: iCloud Drive off, no access, not a backup, newer version, other errors with their message)
  show in Settings → Backup and in the menu bar menu until a backup works.

## Sync (in progress)

iCloud sync of the library between the Mac and an iPhone through CloudKit (the plan, in Czech, is `plan/IOS_SYNC.md`
locally). Built so far: everything in `Shared/Sync/`, the hooks in `AppModel`, the Mac's settings. The iOS app
syncs too (`MobileSync`: on by default when signed in to iCloud, never with `-sampleLibrary`; Settings → Sync).
Checked against iCloud (Development) with a Debug Mac and a Debug iPhone: merging, reading both ways, a feed added
on the iPhone organized on the Mac and back. Missing: deploying the schema to Production.

- Changes of the other device come only by push: `CKSyncEngine.fetchChanges()` fetches only zones a push flagged
  ("no zone IDs needing to be fetched" otherwise), so the fetch before a refresh finds nothing without one. The Mac asks
  for pushes (`NSApp.registerForRemoteNotifications()`), the iOS app has the `remote-notification` background mode.
  Measured: about 1–2 minutes from a change on the iPhone to the Mac.
- The iOS app sends pending changes when it goes to the background (`beginBackgroundTask`); otherwise a change made
  before locking the iPhone waits minutes for iOS to give the suspended app time.
- Articles that come from another device are organized on the Mac once the fetch ended (`SyncController.didFetch`
  → `organize()`; not over half a fetch, whose stories may still come), and a refresh cut short (the iOS app suspended) merges nothing (`Task.isCancelled`), so its
  failed downloads don't mark every feed as failed.
- Testing two Mac instances against each other doesn't show propagation: on one Mac they are one CloudKit device and
  don't get each other's changes. A second instance with an empty home (`CFFIXED_USER_HOME`) does get everything on
  its first, full fetch. The iPhone simulator can't sync: without iCloud Keychain (it can't be turned on there) the
  account is "Temporarily Unavailable" for the encrypted fields. Use a device: `make run-device` (builds, installs
  and launches; `DEVICE=<udid>` when more iPhones are paired, `xcrun devicectl list devices`; the iPhone unlocked,
  Developer Mode on), `xcrun devicectl device capture screenshot`, and `devicectl device copy from --domain-type
  appDataContainer --domain-identifier cz.jsyrovy.feedini --source "Library/Application Support/Feedini/library.json"`
  to compare libraries. Launch a Mac test instance with `open -n --env CFFIXED_USER_HOME=<dir> <app> --args
  -syncsWithICloud YES` (Bool settings read with `as? Bool` need `-key '<false/>'`).

- `SyncSwitch` (both apps) starts and stops syncing as the platform's setting says, in order: after loading and
  after every change of the setting it starts unless it can't run here (`problem`, then the status says why), stops
  when turned off (forgetting the sync state: turning it on again merges), starts after signing in to iCloud
  (`CKAccountChanged`), and turns the setting off when syncing turned off by itself (`onTurnedOff`: Delete iCloud
  Data…, the zone deleted elsewhere – that status stays).
- Mac: Settings → Sync (`SyncSettings`: "Sync with iCloud", `MacPreferences.syncsWithICloud`, off by default, the
  state, Delete iCloud Data… with a confirmation), a line in the menu bar menu while it can't sync. Its `problem` is
  `SyncAvailability.problem()`: the CloudKit entitlement, read with `SecTaskCopyValueForEntitlement` (`CKContainer`
  traps without it), and the iCloud account. Quitting writes the sync state too (`MacServices.flush`). iOS:
  `MobileSync` (on by default; `CloudSyncEngine.accountProblem`, or "not in this build" without `CLOUDKIT`).
- `CloudSyncEngine`: a `CKSyncEngine` over the zone `Library` in the private database of
  `iCloud.cz.jsyrovy.feedini`; it creates the zone on its first start, turns `CKRecord`s into `SyncRecord`s (content
  fields in `encryptedValues`, system fields kept as data) before they reach the main actor, sets only the given
  fields over the zone's record, and maps send failures: `serverRecordChanged` → conflict, `unknownItem` → deleted
  elsewhere, `zoneNotFound` → create the zone and save again, network and account errors → the engine retries.

- `AppModel.sync` (the `SyncController` while sync runs) gets every local change (`apply` with its
  old and new library; reading and saving name their articles, so J/K doesn't compare all of them) and stored page
  text; `applyRemote` applies the zone's changes without sending them back and
  tells the reader (`onRemoteChange`: articles read elsewhere stay in the list like those read here). A refresh
  fetches first (`SyncController.fetch`) and skips retention while a fetch is applied or a merge waits
  (`allowsRetention`).
- `SyncController` (main actor) owns the `SyncState` and an engine behind `SyncEngining` (a fake in tests). It sends
  only the fields changed here over the zone's record (`recordToSend`: all fields for a record the zone doesn't
  have), forgets them once saved (except those changed while sending), applies fetched records (page texts into
  files), merges on the first fetch and then uploads what the zone doesn't have (what differs in the records it has
  is queued by the merge), resolves conflicts and deletions made elsewhere (`sent`, applied in one change), and handles account changes, a deleted zone (turns sync off, `onTurnedOff`), an encrypted data reset
  (uploads everything) and a zone of a newer version (`needsUpdate`).

- One custom zone; record names `<type>-<uuid>` (`SyncRecord.ID`), `settings` and `meta` single. Content fields go
  into `encryptedValues` (`Kind.encryptedFields`); IDs, dates and the folder order stay plain. A tombstone's record
  ID is a hash of its key (`StableID.article`), so lookups by ID go through `SyncRecord.tombstoneKeys`, made once
  per batch (`SyncController` keeps it while the tombstones don't change).
- `SyncStateStore` writes `sync.state`, zlib-compressed JSON: the system fields of a record take about 2.4 KB
  (NSKeyedArchiver), which compress to a tenth (3.3 MB → 0.2 MB for 1000 records), and the state is written again
  after every send (debounced).
- Synced: feeds (not their download state), folders (name, position), articles (content, read and save dates, page
  summary), page texts, stories, topics, tombstones (only the first `lastSeen`), names of removed feeds and the
  summary settings (`Library.summarySettings`, written by the Mac from Settings → AI, the summary language resolved).
  Not synced: download state, AI usage, `pageTextIDs` (follow from the page text records), undo, window state.
- `SyncChanges.diff(old:new:)` finds what to send after a local change, with the fields that changed (kept in
  `SyncState.changedFields` until sent). Changes that came from the zone aren't diffed, so they don't go back.
- `SyncMerge`: an article's content is written once (the first write wins), reading, saving, feeds and folders by the
  last write, stories, topics and the settings only by the Mac. A deletion by the other device keeps an unread or
  saved article, a story or topic with an unread article and the settings, and creates them again. Merging libraries
  (`Mode.merge`): read or saved on either side wins (the earlier date) and the newer page summary (`Article.merge`,
  also used by `StableIDMigration`), folders of the same name become the zone's.
  A conflict when saving takes the zone's record with the fields changed here (not an article's content).
- Compatibility of versions: fields are only added, unknown fields are kept (`SyncRecord.taking`), unknown record
  types are ignored (`SyncRecord.ID(name:)` is `nil`), and a zone needing a newer `SyncSchema.version` stops syncing.

## Update check

`UpdateChecker` (taken over from buddr) asks GitHub for the latest release and tells whether it is newer than the
running app (`CFBundleShortVersionString`). Updates are only reported, never installed.

- One request: `GET https://api.github.com/repos/jsyrovy/feedini/releases/latest` (`LatestRelease`), headers `Accept:
  application/vnd.github+json`, `X-GitHub-Api-Version`, the user agent of the feed downloads (`FeedFetcher.userAgent`;
  GitHub refuses requests without one), ephemeral `URLSession`, timeout 15 s. It answers the latest *published*
  release only – never a draft (`make publish` leaves one) or a prerelease – so the app offers what the Homebrew cask
  offers. Read: `tag_name` (`v0.4`, compared number by number by `AppVersion`, so 0.10 > 0.9) and `html_url` (the
  release page). Without a login GitHub allows 60 requests an hour per IP address; another status than 200 is a
  failure (`UpdateError.status`).
- Settings → General: "Check for updates daily" (`MacPreferences.checksForUpdates`, **off** by default – the request
  tells GitHub the IP address; not in backups) checks at once when switched on or at launch (`MacServices.start`), then
  every 24 h (`UpdateChecker.setDaily`); "Check Now" (`checkNow()`) checks once in any case. A check while one runs is
  skipped; a cancelled one (the loop switched off) leaves the previous result. Nothing is persisted: after a restart
  the result is unknown until the next check.
- Above the checkbox the running version with its commit ("Version 0.4 (4ceb8b3)"); below it: checking, up to date
  ("Feedini is up to date"), a failure (⚠︎ + message), or "Feedini 0.4 is available" with "Download"
  (opens the release page) and, when the Homebrew cask is installed (`HomebrewCask.isInstalled`: `Caskroom/feedini`
  under `/opt/homebrew` or `/usr/local`, looked up once), the `brew upgrade` command, since an update outside Homebrew
  leaves the cask's version behind. The menu bar menu has "Feedini <version> Is Available…" too. No notifications, no
  download or installation (Sparkle was rejected: a third-party dependency).

## Storage and retention

- One file, `~/Library/Application Support/Feedini/library.json`: `{"version": 3, "library": {…}}`, pretty-printed
  with sorted keys and ISO 8601 dates, collections saved as arrays in a stable order (in memory they are
  dictionaries keyed by ID). `LibraryStore.schemaVersion` is bumped with every incompatible change, together with a
  migration in decoding `LibraryStore.File` (shared by loading and restoring a backup; only work on files, like
  moving the old page texts out, stays in `LibraryStore.load()`). Fields added later are optional when decoding (`usage`, `folders` and
  `removedFeeds` via `decodeIfPresent`; `Feed.folderID`, `Story.summary`, `Topic.language`, `Article.pageSummary`,
  `Article.savedAt`, `Article.site`, `Library.summarySettings` as optionals), so older files load without a bump. The version is read before
  the library, so a file from a newer Feedini isn't decoded for nothing.
- Schema versions: 2 saves only articles – a story saved as a whole in a version 1 file (or backup) has its articles
  saved instead, at the story's save date (an article saved already keeps its own date) – and drops the "+1 new"
  marks of stories (`newArticleIDs`, ignored when reading version 1). Feedini 0.1 refuses a version 2 backup as one
  from a newer version. 3 derives feed and article IDs (`StableIDMigration`, below); older Feedini versions refuse a
  version 3 file or backup – say so in the changelog of the release that brings it.
- Stable IDs (`StableID`, schema 3), so that two devices that download the same feed get the same IDs and libraries
  merge by ID: `Feed.id` is a UUID (version 8, from SHA-256) of the feed's normalized address
  (`FeedSubscriber.normalizedAddress`, as `isSame` compares), `Article.id` of the feed's ID and the article's `key`
  – the defaults of `Feed.init` and `Article.init`, so every new feed, article and saved link (`SavedLink.feedID` +
  its key) gets one. Folders, stories and topics keep random IDs. `StableIDMigration` (pure, in decoding a file
  before version 3) rewrites the IDs and every reference: articles, stories and their summaries, tombstones,
  `pageTextIDs`; feeds of `removedFeeds` keep theirs (no address left). Two feeds with the same address become one
  (articles with the same key: `Article.merge`). `LibraryStore.load()` renames
  the page text files and writes the library at once.
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
- `Retention.prune` (pure, run by requested refreshes only, see "Refresh"): unread articles stay forever. Read articles go once their story (or the article alone,
  without a story) has no article younger than `attachWindow` (72 h); each leaves a `Tombstone` (feed + key). A
  tombstone goes once it hasn't been seen in its feed for `tombstoneMargin` (3 days) before the feed's last
  successful download, so a feed that can't be downloaded keeps them. Topics without stories go too.
- Saving (`Article.savedAt`) keeps a saved article forever, but not its story: a story goes once all its articles
  are read and older than `attachWindow`, saved or not; its other articles leave tombstones, the saved ones stay on
  their own, without a story. Removing a feed keeps saved articles too (`articleIDsKeptBySaving`), with the
  feed's name in `Library.removedFeeds` for their source labels (`sourceTitle(of:)`, also in the AI payloads).
  Articles of removed feeds that nothing saved keeps go at the next prune, without a tombstone, and so do the names
  of removed feeds no article comes from.
- Saved links (`SavedLink.feedID`, a feed ID no feed has; `key` is the compared address, `site` the site's name) are
  articles of no feed, so the same rule keeps them only while they are saved. No schema bump was needed.

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
  a page load waits for `pageLoader.waitUntilIdle()` before it ends.
- The shared code is tested only on the Mac (the same code); there is no iOS test target yet. `MacServices.test()`
  gives the Mac services with their model (keep the services in a local: the model holds them weakly),
  `AppModel.test()` the shared model alone, as the iOS app has it.
- Checking the running Mac app: `screencapture` needs the Screen Recording permission (without it: "could not
  create image from display"). Without it, inspect windows with `CGWindowListCopyWindowInfo` (owner `Feedini`). A
  Debug build can run next to an installed Feedini without touching its library: start the binary with
  `CFFIXED_USER_HOME=<empty folder>` (Application Support moves there; UserDefaults stay shared), and quit it by its
  PID – `make run` kills every Feedini.
- Checking the iOS app: `xcrun simctl io booted screenshot <file>` works without Screen Recording, so screens can be
  checked by looking at screenshots: `make run-ios ARGS=-sampleLibrary` shows the made-up `SampleLibrary` (Debug
  only, a temporary store), `-screen list|story|article|saved|settings` opens a screen of it (`-articleView
  pageText|webPage` sets that preference for the launch; the sample links don't load), and `-saveLink
  <address>` saves a page and opens it (its text loads in the hidden web view: that works on iOS too, checked in the
  simulator). Taps and swipes can't be driven yet (no UI tests).

### Test coverage

`make coverage` runs the tests and prints line coverage of the app target. Line-level detail:
`xcrun xccov view --archive --file <absolute path> build/Test.xcresult`.

Coverage is a tool for finding untested behaviour, not a goal. A test must assert observable behaviour (results,
state transitions, the commands that were run), not just execute lines. There is no global percentage target; the
total is dominated by the UI layer, which is deliberately not unit-tested.

Aim for ~100 % in the pure types: `Model/`, `Store/`, `Feeds/`, `Refresh/` (the scheduler with `ManualSleeper`),
`Backup/` (`BackupStore.temporary()`: a temporary folder standing in for iCloud Drive, UTC names), `Updates/`
(`LatestRelease` through a fake transport – never the real GitHub –, `UpdateChecker` with `ManualSleeper`),
`AI/` (the queues with `FakeCommandRunner`, `TestLibraryHost`, `FakePageExtractor` and `ManualSleeper` for the
backoff), `Pages/` (`PageLoader` with `TestLibraryHost` and `FakePageExtractor`), `Summaries/`, `Debug/`,
`KeyboardNavigation`, `ShortcutHelp`, `RelativeTime`, `Preferences`, `MacPreferences`, and `ReadingSession` and
`Reader` (tested with a real `AppModel` over a temporary store). In `PageExtractor` the WebKit callbacks for HTTP errors and failed loads
stay uncovered (they need the network).

Fine to leave uncovered: `App/` (`FeediniMain`, `FeediniApp`, `AppDelegate`, `LoginItem`, `AppModel.start`,
`MacServices.start` and the backup wiring, the non-test branch of `RuntimeEnvironment`, the whole iOS app) and `UI/`
views. Keep these files pure wiring: logic that needs a test
moves into a testable type. Do not add abstractions to production code just to cover lines.

Tests that wait for real time are slow and flaky; timer-driven code takes an injected `sleep` instead. The queues
hold their `LibraryHost` unowned (the app's `AppModel` outlives them) – keep the test host in a local.

## Releasing

Releases are distributed outside the Mac App Store (it only takes sandboxed apps, see README): signed with Developer
ID, hardened runtime, notarized by Apple and stapled, so Gatekeeper opens a downloaded copy without warnings. The
format is a zip of `Feedini.app`, published as a GitHub release of the version's tag, and the Homebrew cask `feedini`
in the tap [`jsyrovy/homebrew-tap`](https://github.com/jsyrovy/homebrew-tap)
(`brew install --cask jsyrovy/tap/feedini`). Not in `homebrew/cask`: a self-submitted cask needs 90 forks, 90
watchers or 225 stars on GitHub.

- A release is made only by hand, never by a push. Between releases the version stays the last released one.
- Steps: set `MARKETING_VERSION` to the new `major.minor` (Xcode: target → General → Version, or both configurations in
  the pbxproj), add a section `## <version> – <YYYY-MM-DD>` to `CHANGELOG.md` (a few lines for users, drafted from
  `git log v<previous>..HEAD`), commit ("Release 0.2"), `git tag v0.2`, `make release`, `git push origin main v0.2`,
  `make publish`, then check the draft on GitHub and publish it. The tag is pushed only after a successful release; if
  it fails, fix, commit and move the unpushed tag (`git tag -f`).
- `scripts/release.sh` changes nothing in git. It checks the preconditions first (clean tree, tag, dated changelog
  section, identity, notary profile, the installed provisioning profile "Feedini Developer ID" of the app with its
  iCloud container, not expired), then archives (signed manually with Developer ID and that profile right away, so
  there is no export step; build number = `git rev-list --count HEAD`), checks the signature and the entitlements
  (CloudKit, Production, push production, no `get-task-allow`), notarizes, staples, zips and checks the zip as a
  download with `syspolicy_check distribution`. A run takes a few minutes, most of it notarization.
- Output: `build/release/Feedini-<version>.zip`, its `.sha256`, `Feedini-<version>-dSYMs.zip` (for symbolicating
  crash reports) and the archive.
- `scripts/publish.sh` (needs `gh`, logged in) uploads the zip, its checksum and the dSYMs as a *draft* release of the
  tag, with the tag's `CHANGELOG.md` section as the notes; publishing stays a step on GitHub. It refuses when the zip
  doesn't match its checksum or wasn't built from the tag (build number), the tag isn't on GitHub as it is locally, or
  the release exists already.
- The cask (`Casks/feedini.rb` in the tap) is updated by `.github/workflows/homebrew.yml` when a release is published
  (never for a draft or a prerelease): it checks the zip of the release against its `.sha256`, sets `version` and
  `sha256` and pushes to the tap with a deploy key with write access (secret `HOMEBREW_TAP_DEPLOY_KEY` of this
  repository). It refuses a version older than the cask's and changes nothing when the cask has it already; run it by
  hand (`gh workflow run homebrew.yml -f tag=v0.2`) to retry. Checking a change of the cask itself: the tap's README.
- Credentials live in the login keychain only, never in the repo: the identity "Developer ID Application: Jiri Syrovy
  (DZ7S6R9RRN)" (expires 2027-12-05; renew it before, already shipped versions keep working thanks to the timestamp)
  and the `notarytool` keychain profile `notary` (an App Store Connect API team key with the Developer role;
  `NOTARY_PROFILE` overrides the name). Both belong to the team, not to Feedini; the owner keeps backups outside the
  repo. The Developer ID provisioning profile "Feedini Developer ID" (App ID `cz.jsyrovy.feedini` with iCloud /
  CloudKit and Push Notifications; valid until 2044) is installed in `~/Library/Developer/Xcode/UserData/Provisioning
  Profiles/`, a copy kept by the owner outside the repo; a new one is made in the developer portal (Profiles →
  Distribution → Developer ID) after a change of the App ID's capabilities.
- Hardened runtime: Release builds (`make install`, CI) have it too, so everyday use runs like a release. It stays off
  in Debug: forced on, library validation rejects the ad-hoc test bundle. No hardened runtime exceptions are needed:
  WebKit runs its content in its own processes, and `claude` is a process of its own with its own signature.
- A Developer ID build is a different code identity than a development one: macOS may ask again for access to iCloud
  Drive, and a login item registered by another build may need turning off and on.
- Pitfall: `syspolicy_check notary-submission` includes a Gatekeeper assessment and rejects every app that is not
  notarized yet, so it can't serve as a check before notarization.

## Logs

`os.Logger` subsystem `cz.jsyrovy.feedini`, categories `refresh`, `feeds`, `ai` (one line per call with the metrics
of the answer), `store`, `backup`, `updates` and `sync`. Watch with
`/usr/bin/log stream --level info --predicate 'subsystem == "cz.jsyrovy.feedini"'` – in zsh, plain `log` is a shell
builtin. The test host is also called Feedini; filter by `processID` to see only the running app.
