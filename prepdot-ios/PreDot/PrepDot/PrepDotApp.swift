import SwiftUI

@main
struct PrepdotApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AuthManager.shared)
        }
    }
}
