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

    /// The name of a language in itself: `cs` → "čeština".
    static func nativeName(of code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code) ?? name(of: code)
    }

    /// The languages offered in Settings: the most common ones for news.
    static let choices = [
        "ar", "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "he", "hi", "hr", "hu", "id", "it", "ja",
        "ko", "lt", "lv", "nb", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sr", "sv", "th", "tr", "uk", "vi", "zh",
    ]
}
