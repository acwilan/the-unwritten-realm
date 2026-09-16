import SwiftUI

@main
struct TheUnwrittenRealmApp: App {
    @StateObject private var session = GameSession()
    @AppStorage("selectedLanguage") private var selectedLanguageCode = AppLanguage.english.rawValue

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguageCode) ?? .english
    }

    var body: some Scene {
        WindowGroup {
            ContentView(session: session, selectedLanguageCode: $selectedLanguageCode)
                .environment(\.locale, selectedLanguage.locale)
                .environment(\.appLanguage, selectedLanguage)
        }
    }
}
