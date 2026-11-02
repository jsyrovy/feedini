import Testing

@testable import Feedini

struct ShortcutHelpTests {
    @Test func everyKeyIsListedOnceInItsGroup() {
        let sections = ShortcutHelp.sections(opensInWindow: true, aiProblem: nil)
        #expect(sections.map(\.group) == ShortcutHelp.Group.allCases)
        let keys = sections.flatMap { $0.items.map(\.keys) }
        #expect(keys.count == ListKey.allCases.count + 1)
        #expect(Set(keys).count == keys.count)
        #expect(
            sections.map { $0.items.map(\.keys) } == [
                ["J / ↓", "K / ↑", "L / →", "H / ←", "Esc"],
                ["M", "S", "R", "Shift+A"],
                ["V / Enter", "Shift+V / Shift+Enter", "P", "T"],
                ["?", "⌘,"],
            ])
    }

    @Test func openingFollowsTheSetting() {
        let open = ShortcutHelp.item(for: .open, opensInWindow: false, aiProblem: nil).1
        let other = ShortcutHelp.item(for: .openOther, opensInWindow: false, aiProblem: nil).1
        #expect(open.description == "Open the source page in the browser")
        #expect(other.description == "Open the source page in Feedini")
    }

    @Test func summarizingSaysWhyAIIsUnavailable() {
        let sections = ShortcutHelp.sections(opensInWindow: true, aiProblem: AIStatus.State.off.problem)
        let unavailable = sections.flatMap(\.items).filter { $0.unavailable != nil }
        #expect(unavailable.map(\.keys) == ["T"])
    }
}
