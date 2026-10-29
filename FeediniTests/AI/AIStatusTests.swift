import Testing

@testable import Feedini

@MainActor
struct AIStatusTests {
    @Test func problemsSayWhyAICannotRun() {
        #expect(AIStatus.State.idle.problem == nil)
        #expect(AIStatus.State.organizing(3).problem == nil)
        #expect(AIStatus.State.off.problem == "AI is off (Settings → AI).")
        #expect(AIStatus.State.unavailable("claude not found").problem == "AI unavailable: claude not found")
    }

    @Test func theStatusLineNamesAnUnavailableAIButNotAnOffOne() {
        let status = AIStatus()
        status.set(.unavailable("claude not found"))
        #expect(status.message == "AI unavailable: claude not found")
        status.set(.off)
        #expect(status.message == nil)
    }
}
