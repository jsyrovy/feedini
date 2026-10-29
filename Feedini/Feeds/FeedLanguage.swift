import Foundation
import NaturalLanguage

/// The language of articles: the feed's own `<language>` when it gives one, otherwise detected on the device from the
/// title and text.
enum FeedLanguage {
    /// The primary language code of a language tag: `cs-CZ` → `cs`, `en_us` → `en`. `nil` for anything that doesn't
    /// look like a language tag.
    static func code(_ tag: String?) -> String? {
        guard let tag else { return nil }
        let primary =
            tag.trimmingCharacters(in: .whitespaces).lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? ""
        guard (2...3).contains(primary.count), primary.allSatisfy({ $0 >= "a" && $0 <= "z" }) else { return nil }
        return String(primary)
    }

    /// The language of an article of a feed with the given language code.
    static func language(feedLanguage: String?, title: String, text: String) -> String? {
        feedLanguage ?? detect("\(title)\n\(text.prefix(maxDetectedCharacters))")
    }

    /// The dominant language of the text, if the recognizer is reasonably sure.
    static func detect(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, probability) = recognizer.languageHypotheses(withMaximum: 1).first,
            probability >= minimumConfidence
        else { return nil }
        return code(language.rawValue)
    }

    static let minimumConfidence = 0.5
    static let maxDetectedCharacters = 600
}
