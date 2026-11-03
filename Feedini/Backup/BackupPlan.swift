import Foundation

/// How often automatic backups run (Settings → Backup).
enum BackupFrequency: String, CaseIterable, Sendable {
    case hourly, daily, weekly

    var interval: TimeInterval {
        switch self {
        case .hourly: 60 * 60
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        }
    }
}

/// When to back up and which backups to keep (pure).
enum BackupPlan {
    /// Every backup of the last day is kept, …
    static let keepsAll: TimeInterval = 24 * 60 * 60
    /// … then the newest of every day for two weeks, …
    static let keepsDaily: TimeInterval = 14 * 24 * 60 * 60
    /// … then the newest of every week for eight weeks; older ones go.
    static let keepsWeekly: TimeInterval = 8 * 7 * 24 * 60 * 60

    /// Whether the next automatic backup is due. The check runs after refreshes (every 5–60 minutes), so a backup
    /// counts as due once 90 % of the interval passed – otherwise an hourly backup would slip by a whole refresh
    /// interval every time.
    static func isDue(lastBackup: Date?, frequency: BackupFrequency, now: Date) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= frequency.interval * 0.9
    }

    /// The backups (by their dates) to delete, thinned out like Time Machine: all of the last day, the newest of
    /// every day for two weeks, the newest of every week for eight weeks. The newest backup always stays.
    static func expired(_ dates: [Date], now: Date, calendar: Calendar = .current) -> Set<Date> {
        var expired: Set<Date> = []
        var days: Set<DateComponents> = []
        var weeks: Set<DateComponents> = []
        for (position, date) in dates.sorted(by: >).enumerated() {
            let age = now.timeIntervalSince(date)
            let isNewestOfDay = days.insert(calendar.dateComponents([.era, .year, .month, .day], from: date)).inserted
            let isNewestOfWeek = weeks.insert(calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
                .inserted
            let keeps =
                position == 0 || age < keepsAll || (age < keepsDaily && isNewestOfDay)
                || (age >= keepsDaily && age < keepsWeekly && isNewestOfWeek)
            if !keeps {
                expired.insert(date)
            }
        }
        return expired
    }
}
