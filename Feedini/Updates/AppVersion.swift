import Foundation

/// A version of Feedini, `major.minor` (`MARKETING_VERSION`, release tags `v<major.minor>`), compared number by
/// number, so 0.10 is newer than 0.9.
struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    let components: [Int]

    /// Reads "0.3" or a tag "v0.3"; any number of components. `nil` for anything else.
    init?(_ text: String) {
        let number = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
        var components: [Int] = []
        for part in parts {
            // Digits only: `Int` would also take "+3". It refuses an empty part and one too big.
            guard part.allSatisfy({ "0"..."9" ~= $0 }), let number = Int(part) else { return nil }
            components.append(number)
        }
        self.components = components
    }

    /// The version of the running app (`CFBundleShortVersionString`).
    static let current = AppVersion(RuntimeEnvironment.appVersion)

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    /// Missing components count as 0: 0.3 equals 0.3.0.
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
