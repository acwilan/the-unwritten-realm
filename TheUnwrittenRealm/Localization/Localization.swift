import Foundation
import SwiftUI

/// Languages the app can display independently of the device's system language.
/// English is deliberately the first case and the fallback for missing entries.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case spanish = "es"
    case portuguese = "pt"
    case french = "fr"
    case german = "de"
    case italian = "it"

    public var id: String { rawValue }
    public var locale: Locale { Locale(identifier: rawValue) }

    public var displayNameKey: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .portuguese: return "Portuguese"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        }
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguage.english
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
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
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

struct LanguagePicker: View {
    @Binding var selectedLanguageCode: String

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguageCode) ?? .english
    }

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    selectedLanguageCode = language.rawValue
                } label: {
                    HStack {
                        Text(LocalizedStringKey(language.displayNameKey))
                        if selectedLanguage == language {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Language", systemImage: "globe")
        }
        .accessibilityLabel("Language")
    }
}
