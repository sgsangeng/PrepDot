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
                .tabItem { Label("知识树", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(1)
            LearningCoachView()
                .tabItem { Label("学习教练", systemImage: "sparkles") }
                .tag(2)
            ProfileTabView()
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
                .tag(3)
        }
        .tint(.indigo)
    }
}
