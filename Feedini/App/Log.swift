import os

/// Loggers of the app, subsystem `cz.jsyrovy.feedini`.
enum Log {
    private static let subsystem = "cz.jsyrovy.feedini"

    static let refresh = Logger(subsystem: subsystem, category: "refresh")
    static let feeds = Logger(subsystem: subsystem, category: "feeds")
    static let ai = Logger(subsystem: subsystem, category: "ai")
    static let store = Logger(subsystem: subsystem, category: "store")
}
