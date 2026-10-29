import Foundation

/// Files from `FeediniTests/Fixtures`, copied flat into the test bundle as resources.
enum Fixture {
    private final class BundleToken {}

    /// `name` includes the extension, e.g. `"rss2.xml"`.
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let url = URL(fileURLWithPath: name)
        guard
            let resource = bundle.url(
                forResource: url.deletingPathExtension().lastPathComponent, withExtension: url.pathExtension)
        else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: resource)
    }

    enum FixtureError: Error {
        case missing(String)
    }
}
