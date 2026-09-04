import SwiftUI

@main
struct TheUnwrittenRealmApp: App {
    @StateObject private var session = GameSession()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
        }
    }
}
