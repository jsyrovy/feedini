import Foundation

/// The language AI output is written in, named in English for the prompt ("Czech").
enum OutputLanguage {
    /// The primary language code of the system (`cs`), `en` when unknown.
    static var systemCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// The English name of a language code: `cs` → "Czech".
    static func name(of code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }
}
