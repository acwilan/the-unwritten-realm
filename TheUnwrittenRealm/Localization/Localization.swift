import Foundation
import SwiftUI

/// Languages shipped with the app. English is the final fallback for missing entries.
public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case spanish = "es"
    case portuguese = "pt"
    case french = "fr"
    case german = "de"
    case italian = "it"

    public var id: String { rawValue }
    public var locale: Locale { Locale(identifier: rawValue) }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .portuguese: return "Portuguese"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        }
    }

    public var speechLanguageCodes: [String] {
        switch self {
        case .english: return ["en-US", "en-GB"]
        case .spanish: return ["es-MX", "es-ES", "es-US"]
        case .portuguese: return ["pt-BR", "pt-PT"]
        case .french: return ["fr-FR", "fr-CA"]
        case .german: return ["de-DE"]
        case .italian: return ["it-IT"]
        }
    }

    /// Resolves in Apple's normal order: per-app language setting, OS preference, English.
    public static var current: AppLanguage {
        for localization in Bundle.main.preferredLocalizations {
            let code = localization.split { $0 == "-" || $0 == "_" }.first.map(String.init)
            if let code, let language = AppLanguage(rawValue: code) {
                return language
            }
        }
        return .english
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguage.current
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

/// Resolves strings from the selected locale's `.lproj` bundle.
public enum AppLocalization {
    public static func string(_ key: String, language: AppLanguage) -> String {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
        }
        let localized = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        guard localized == key, language != .english,
              let englishPath = Bundle.main.path(forResource: AppLanguage.english.rawValue, ofType: "lproj"),
              let englishBundle = Bundle(path: englishPath) else { return localized }
        return englishBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    public static func format(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        String(format: string(key, language: language), locale: language.locale, arguments: arguments)
    }
}

public extension Attribute {
    var localizedDisplayNameKey: String {
        switch self {
        case .might: return "Might"
        case .finesse: return "Finesse"
        case .insight: return "Insight"
        case .presence: return "Presence"
        }
    }

    func localizedDisplayName(in language: AppLanguage) -> String {
        AppLocalization.string(localizedDisplayNameKey, language: language)
    }
}

public extension CharacterType {
    func localizedDisplayName(in language: AppLanguage) -> String {
        AppLocalization.string(displayName, language: language)
    }

    func localizedSummary(in language: AppLanguage) -> String {
        AppLocalization.string(summary, language: language)
    }
}

public extension CharacterAbility {
    func localizedName(in language: AppLanguage) -> String {
        AppLocalization.string(name, language: language)
    }

    func localizedDescription(in language: AppLanguage) -> String {
        AppLocalization.string(description, language: language)
    }
}

public extension CampaignDifficulty {
    var localizedDisplayNameKey: String {
        switch self {
        case .easy: return "Easy"
        case .difficult: return "Difficult"
        }
    }

    var localizedDescriptionKey: String {
        switch self {
        case .easy: return "Lower target values give you more room to experiment."
        case .difficult: return "Higher target values make risky actions less forgiving."
        }
    }

    func localizedDisplayName(in language: AppLanguage) -> String {
        AppLocalization.string(localizedDisplayNameKey, language: language)
    }

    func localizedDescription(in language: AppLanguage) -> String {
        AppLocalization.string(localizedDescriptionKey, language: language)
    }
}
