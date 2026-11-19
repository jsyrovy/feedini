import Testing

@testable import Feedini

struct AppVersionTests {
    @Test(arguments: [("0.3", [0, 3]), ("v0.3", [0, 3]), ("1.10.2", [1, 10, 2]), ("7", [7])])
    func readsVersionsAndTags(text: String, components: [Int]) {
        #expect(AppVersion(text)?.components == components)
    }

    @Test(arguments: ["", "v", "0.", ".3", "0..3", "0.3-beta", "+0.3", "0.-3", "V0.3", "0.٣", "0.99999999999999999999"])
    func refusesAnythingElse(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func comparesNumberByNumber() throws {
        let versions = try ["0.9", "0.10", "1.0", "0.3", "0.3.1"].map { try #require(AppVersion($0)) }
        #expect(versions.sorted().map(\.description) == ["0.3", "0.3.1", "0.9", "0.10", "1.0"])
    }

    @Test func missingComponentsCountAsZero() throws {
        let short = try #require(AppVersion("0.3"))
        let long = try #require(AppVersion("0.3.0"))
        #expect(short == long)
        #expect(!(short < long))
        #expect(!(long < short))
        #expect(try short != #require(AppVersion("0.3.1")))
    }

    @Test func hostAppHasAVersion() {
        #expect(AppVersion.current != nil)
    }
}
