import Foundation
import Testing

@testable import Feedini

struct ClaudeLocatorTests {
    private func locator(
        executables: Set<String>, path: String? = "/usr/bin:/opt/homebrew/bin:/custom/bin"
    )
        -> ClaudeLocator
    {
        ClaudeLocator(homeDirectory: "/Users/me", searchPath: path, isExecutable: { executables.contains($0) })
    }

    @Test func searchesTheInstallLocationsBeforeThePath() {
        #expect(
            locator(executables: []).directories == [
                "/Users/me/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/custom/bin",
            ])
        #expect(locator(executables: [], path: nil).directories.count == 3)
    }

    @Test func findsTheFirstExecutable() {
        let both = locator(executables: ["/Users/me/.local/bin/claude", "/custom/bin/claude"])
        #expect(both.locate() == URL(fileURLWithPath: "/Users/me/.local/bin/claude"))
        #expect(locator(executables: ["/custom/bin/claude"]).locate() == URL(fileURLWithPath: "/custom/bin/claude"))
        #expect(locator(executables: []).locate() == nil)
    }

    @Test func aCustomPathWins() {
        let locator = locator(executables: ["/Users/me/.local/bin/claude", "/tools/claude"])
        #expect(locator.locate(customPath: " /tools/claude ") == URL(fileURLWithPath: "/tools/claude"))
        #expect(locator.locate(customPath: "/missing/claude") == nil)
        #expect(locator.locate(customPath: "") == URL(fileURLWithPath: "/Users/me/.local/bin/claude"))
    }
}
