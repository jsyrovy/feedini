# Feedini 🎩

Your RSS feeds, magically organized and summarized.

Feedini is a native macOS RSS reader driven by the keyboard. It groups articles about the same event from different
feeds into one story, sorts stories into topics and writes short summaries – in your language – where they help:
for stories covered by several sources and for articles in other languages. The AI runs through the
Claude Code CLI you already have; without it, Feedini is a plain, fast feed reader.

New articles show up right away; grouping and summaries arrive in the background, so the AI never makes you wait.

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

## Roadmap

- [x] F0: project setup, an empty app
- [x] F1: a reader without AI – feeds, OPML, keyboard navigation, read state, source pages
- [x] F2: AI grouping into stories and topics
- [x] F3: summaries in your language
- [ ] F4: running in the menu bar, background refresh
- [ ] F5: polish – performance with thousands of articles, AI statistics, screenshots

## License

[MIT](LICENSE)
