# Feedini 🎩

Your RSS feeds, magically organized and summarized.

Feedini is a native macOS RSS reader driven by the keyboard. It groups articles about the same event from different
feeds into one story, sorts stories into topics and writes short summaries – in your language – where they help:
for stories covered by several sources and for articles in other languages. The AI runs through the
Claude Code CLI you already have; without it, Feedini is a plain, fast feed reader.

New articles show up right away; grouping and summaries arrive in the background, so the AI never makes you wait.

## Features

- **Stories, not duplicates.** Ten articles about one product launch from three sites are one story with one
  summary; expand it to read the articles one by one.
- **Topics** that the AI keeps stable as new articles arrive, next to your feeds in the sidebar.
- **Summaries in your language** for stories with several articles. Single articles keep their own text, unless you
  choose to summarize those in other languages (a translated gist) or all of them.
- **Keyboard first**: J / K to move, L / H to expand and collapse, V / Enter to open the source page (in the window
  or the browser), M to toggle read, R to refresh, Shift+A to mark everything read, ? for all the shortcuts.
- **The whole article** when the feed only has its first lines: P shows the full text of the source page, T a TL;DR
  of it (with the key details for longer articles).
- **Read means read**: moving onto an item marks it read; read items leave the list when you switch views or
  refresh, and a refresh never brings them back.
- **Runs in the menu bar** after you close the window, refreshing and organizing in the background, with the unread
  count next to the 🎩.
- Feeds by address or OPML import / export (with their folders); RSS 0.9x, 1.0, 2.0 and Atom. Folders of your own
  in the sidebar: drag feeds into them and the folders into your order.

## Privacy and cost

- Feedini only reads what the feeds contain. It downloads a web page only when you ask for it: the page you open
  (V), its full text (P) or its summary (T). Only T sends the page's text to the AI. If you are logged in on the
  site, the text may include what the page shows about you (such as "Logged in as …").
- The AI gets titles and the start of the feed texts through the `claude` CLI, with all of its tools turned off.
- With the default model (Claude Haiku) organizing new articles costs about $0.002–0.005 per batch of 20 and a
  summary of ten stories about $0.004; Settings → AI shows the calls, time and cost per day.

## Requirements

- macOS 15 or later.
- Optional, for AI: the Claude Code CLI (`claude`), signed in. Feedini looks for it in `~/.local/bin`,
  `/opt/homebrew/bin`, `/usr/local/bin` and your `PATH`; the path can be set in Settings.
- Feeds must be served over HTTPS.

## Building from source

Xcode 27 is required; there are no other dependencies.

```bash
make run       # Debug build, then open the app
make install   # Release build into ~/Applications
make test      # unit tests
```

## Why not in the Mac App Store

Feedini runs the `claude` command-line tool, which a sandboxed app can't do, and the Mac App Store only accepts
sandboxed apps.

## License

[MIT](LICENSE)
