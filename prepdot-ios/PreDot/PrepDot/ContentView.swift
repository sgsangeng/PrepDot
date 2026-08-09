import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) var auth
    @State private var selectedTab = 0

    var body: some View {
        if auth.isLoggedIn { mainView } else { LoginView() }
    }

    private var mainView: some View {
        TabView(selection: $selectedTab) {
            ReviewView(selectedTab: $selectedTab)
                .tabItem { Label("今日复习", systemImage: "brain.head.profile") }
                .tag(0)
            DecksView()
                .tabItem { Label("我的卡组", systemImage: "rectangle.stack.fill") }
                .tag(1)
            ProfileTabView()
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
                .tag(2)
        }
        .tint(.indigo)
    }
}
