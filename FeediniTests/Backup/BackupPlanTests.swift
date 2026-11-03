import Foundation
import Testing

@testable import Feedini

struct BackupPlanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    @Test func isDueWithoutABackupAndOnceMostOfTheIntervalPassed() {
        #expect(BackupPlan.isDue(lastBackup: nil, frequency: .weekly, now: referenceDate))
        // An hourly backup made at a quarter past is due at the refresh just before the next quarter past.
        #expect(!BackupPlan.isDue(lastBackup: .hours(0), frequency: .hourly, now: .hours(0.8)))
        #expect(BackupPlan.isDue(lastBackup: .hours(0), frequency: .hourly, now: .hours(0.9)))
        #expect(!BackupPlan.isDue(lastBackup: .hours(0), frequency: .daily, now: .hours(21)))
        #expect(BackupPlan.isDue(lastBackup: .hours(0), frequency: .daily, now: .hours(22)))
        #expect(!BackupPlan.isDue(lastBackup: .hours(0), frequency: .weekly, now: .hours(150)))
        #expect(BackupPlan.isDue(lastBackup: .hours(0), frequency: .weekly, now: .hours(152)))
    }

    @Test func keepsTheLastDayThenOneADayThenOneAWeek() {
        // Hourly backups for ten weeks; `referenceDate` is a Thursday noon.
        let dates = (0..<(10 * 7 * 24)).map { Date.hours(-Double($0)) }

        let expired = BackupPlan.expired(dates, now: referenceDate, calendar: calendar)
        let kept = dates.filter { !expired.contains($0) }

        // The last 24 hours.
        #expect(kept.filter { $0 > .hours(-24) }.count == 24)
        // One a day (the newest of it) from there to two weeks.
        let daily = kept.filter { $0 <= .hours(-24) && $0 > .hours(-14 * 24) }
        #expect(daily.allSatisfy { calendar.component(.hour, from: $0) == 23 })
        #expect(Set(daily.map { calendar.startOfDay(for: $0) }).count == daily.count)
        // One a week from there to eight weeks, nothing older.
        let weekly = kept.filter { $0 <= .hours(-14 * 24) }
        #expect(weekly.allSatisfy { $0 > .hours(-8 * 7 * 24) })
        #expect(
            Set(weekly.map { calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0) }).count
                == weekly.count)
        #expect((5...7).contains(weekly.count))
        #expect(kept.count == 24 + daily.count + weekly.count)
        #expect(kept.count < 50)
    }

    @Test func keepsTheNewestBackupHoweverOld() {
        let old = Date.hours(-100 * 24)
        let older = Date.hours(-101 * 24)

        #expect(BackupPlan.expired([older, old], now: referenceDate, calendar: calendar) == [older])
        #expect(BackupPlan.expired([], now: referenceDate, calendar: calendar).isEmpty)
    }

    @Test func aDayOrWeekWithANewerBackupNeedsNoOther() {
        // Two backups of the same day, older than a day: only the newer one stays.
        let evening = Date.hours(-26)
        let morning = Date.hours(-34)
        // A backup of the future (another Mac's clock) counts as new.
        let future = Date.hours(2)

        let expired = BackupPlan.expired([morning, evening, future], now: referenceDate, calendar: calendar)

        #expect(expired == [morning])
    }
}
