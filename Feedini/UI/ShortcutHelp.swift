import Foundation

/// The keyboard shortcuts shown by ? (pure). Every `ListKey` has its line in the `switch` of `item(for:)`, so a new
/// key doesn't compile without one.
enum ShortcutHelp {
    enum Group: String, CaseIterable, Sendable {
        case moving = "Moving"
        case reading = "Reading"
        case pageAndAI = "Page and AI"
        case other = "Other"
    }

    struct Item: Equatable, Sendable, Identifiable {
        var keys: String
        var description: String
        /// Why the shortcut does nothing now, if it doesn't.
        var unavailable: String?

        var id: String { keys }
    }

    struct Section: Equatable, Sendable, Identifiable {
        var group: Group
        var items: [Item]

        var id: Group { group }
    }

    /// - Parameters:
    ///   - opensInWindow: the default way of opening source pages (Settings → General).
    ///   - aiProblem: why AI can't run (`AIStatus.State.problem`), if it can't.
    static func item(for key: ListKey, opensInWindow: Bool, aiProblem: String?) -> (Group, Item) {
        let inWindow = "Open the source page in Feedini"
        let inBrowser = "Open the source page in the browser"
        return switch key {
        case .next: (.moving, Item(keys: "J / ↓", description: "Next item (article inside an expanded story)"))
        case .previous: (.moving, Item(keys: "K / ↑", description: "Previous item"))
        case .expand: (.moving, Item(keys: "L / →", description: "Expand the story"))
        case .collapse: (.moving, Item(keys: "H / ←", description: "Collapse the story (from an article: its story)"))
        case .escape: (.moving, Item(keys: "Esc", description: "Back from the source page, or collapse the story"))
        case .open: (.pageAndAI, Item(keys: "V / Enter", description: opensInWindow ? inWindow : inBrowser))
        case .openOther:
            (.pageAndAI, Item(keys: "Shift+V / Shift+Enter", description: opensInWindow ? inBrowser : inWindow))
        case .preview:
            (.pageAndAI, Item(keys: "P", description: "Full text of the source page instead of the feed text"))
        case .summarizePage:
            (.pageAndAI, Item(keys: "T", description: "Summarize the source page (TL;DR)", unavailable: aiProblem))
        case .toggleRead: (.reading, Item(keys: "M", description: "Mark as read / unread"))
        case .save: (.reading, Item(keys: "S", description: "Save for later / remove from Saved"))
        case .refresh: (.reading, Item(keys: "R", description: "Refresh now"))
        case .markAllRead: (.reading, Item(keys: "Shift+A", description: "Mark everything in the selection as read"))
        case .shortcuts: (.other, Item(keys: "?", description: "Keyboard shortcuts"))
        }
    }

    static func sections(opensInWindow: Bool, aiProblem: String?) -> [Section] {
        let items = ListKey.allCases.map { item(for: $0, opensInWindow: opensInWindow, aiProblem: aiProblem) }
        return Group.allCases.map { group in
            var section = Section(group: group, items: items.filter { $0.0 == group }.map(\.1))
            if group == .other {
                section.items.append(Item(keys: "⌘,", description: "Settings"))
            }
            return section
        }
    }
}
