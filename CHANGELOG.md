# Changelog

## 0.2 – 2026-11-26

- iCloud sync (Settings → Sync, off by default): your feeds, folders, reading, saved articles, stories and summaries
  on your Macs signed in to the same iCloud account. An iPhone app is on its way.
- Stories show only what is new: their unread articles, and their summaries are written from those only. Only
  articles are saved, never a whole story.
- Settings → General → "Show articles as": the feed text (as before), the text of the source page or the web page
  when you move onto an article.
- Sort the list newest or oldest first (View → Sort, or the toolbar).
- Check for a newer Feedini daily (Settings → General, off by default) or on request; a new version shows in the
  menu bar menu too. Settings shows the running version with its commit.
- The article detail has a Save / Saved toggle, and a story's detail marks its saved articles.
- List rows show the age first, so a long feed name never hides it.
- Only a refresh you ask for (R, launch, wake) clears read articles from the list; a scheduled one only adds new ones.
- Letter keys in the list no longer jump to (and read) a row starting with that letter.
- The library and backups get a new format: Feedini 0.1 can't open them. Back up before upgrading if you might go
  back.

## 0.1 – 2026-11-05

The first release.

- A native macOS RSS reader driven by the keyboard: J / K to move, V to open the source page, M to toggle read, ? for
  all the shortcuts. RSS 0.9x, 1.0, 2.0 and Atom over HTTPS; feeds by address or OPML import and export, in folders
  of your own.
- With the Claude Code CLI (`claude`): articles about the same event from different feeds become one story, stories
  are sorted into topics, and summaries in your language are written where they help. Without it, Feedini is a
  plain, fast feed reader.
- P shows the full text of an article's source page, T a TL;DR of it.
- Saved for later: S keeps a story or an article, Save Link… keeps any web page by its address.
- ⌘Z takes back reading and saving step by step.
- Keeps running in the menu bar after you close the window, with the unread count next to the hat.
- Automatic backups to iCloud Drive (off by default), and restoring a chosen backup.
- Requires macOS 15 or later.
