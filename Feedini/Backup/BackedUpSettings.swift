/// The settings that go into a backup. Those of one Mac stay out (the path to claude, the folders collapsed in the
/// sidebar, opening at login), and so do those of backing up: restoring an old backup mustn't turn backups off. Values
/// are kept as they were; restoring applies the valid ones (`Preferences.apply`).
struct BackedUpSettings: Codable, Sendable, Equatable {
    var refreshMinutes: Int?
    var pageOpening: String?
    var showsUnreadCount: Bool?
    var aiEnabled: Bool?
    var assignModel: String?
    var summaryModel: String?
    var aiEffort: String?
    var summaryLanguage: String?
    var singleArticleSummaries: String?
}

extension Preferences {
    var backedUpSettings: BackedUpSettings {
        BackedUpSettings(
            refreshMinutes: refreshMinutes, pageOpening: pageOpening.rawValue, showsUnreadCount: showsUnreadCount,
            aiEnabled: aiEnabled, assignModel: assignModel, summaryModel: summaryModel, aiEffort: aiEffort,
            summaryLanguage: summaryLanguage, singleArticleSummaries: singleArticleSummaries.rawValue)
    }

    /// Takes over the settings of a backup; missing values and those that aren't valid (offered) any more are left
    /// as they are – the same rules as for the stored values.
    func apply(_ settings: BackedUpSettings) {
        if let minutes = Self.refreshMinutes(settings.refreshMinutes) {
            refreshMinutes = minutes
        }
        if let opening = settings.pageOpening.flatMap(PageOpening.init(rawValue:)) {
            pageOpening = opening
        }
        if let shows = settings.showsUnreadCount {
            showsUnreadCount = shows
        }
        if let enabled = settings.aiEnabled {
            aiEnabled = enabled
        }
        if let model = Self.model(settings.assignModel) {
            assignModel = model
        }
        if let model = Self.model(settings.summaryModel) {
            summaryModel = model
        }
        if let effort = Self.effort(settings.aiEffort) {
            aiEffort = effort
        }
        if let language = Self.summaryLanguage(settings.summaryLanguage) {
            summaryLanguage = language
        }
        if let summaries = settings.singleArticleSummaries.flatMap(SingleArticleSummaries.init(rawValue:)) {
            singleArticleSummaries = summaries
        }
    }
}
