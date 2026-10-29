import Foundation

/// Finds the `claude` executable.
///
/// Apps started from the Finder don't inherit the shell `PATH`, so the usual install locations are searched first:
/// `~/.local/bin` (the native installer), Homebrew, then `PATH`. A path set in Settings wins.
struct ClaudeLocator: Sendable {
    var homeDirectory: String
    var searchPath: String?
    var isExecutable: @Sendable (String) -> Bool

    init(
        homeDirectory: String = NSHomeDirectory(), searchPath: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.homeDirectory = homeDirectory
        self.searchPath = searchPath
        self.isExecutable = isExecutable
    }

    /// Directories searched in order, each once.
    var directories: [String] {
        let fixed = ["\(homeDirectory)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        let path = (searchPath ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (fixed + path).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The custom path when given (`nil` if it isn't executable), otherwise the first `claude` found.
    func locate(customPath: String? = nil) -> URL? {
        if let customPath = customPath?.trimmingCharacters(in: .whitespaces), !customPath.isEmpty {
            let expanded = (customPath as NSString).expandingTildeInPath
            return isExecutable(expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        for directory in directories {
            let path = "\(directory)/claude"
            if isExecutable(path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
