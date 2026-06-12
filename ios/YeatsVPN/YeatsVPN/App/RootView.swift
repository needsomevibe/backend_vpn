import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()
            switch environment.route {
            case .splash:
                SplashView()
            case .login:
                LoginView(viewModel: AuthViewModel(environment: environment))
            case .register:
                RegisterView(viewModel: AuthViewModel(environment: environment))
            case .main:
                MainTabsView()
            }
        }
        .animation(.snappy(duration: 0.28), value: environment.route)
    }
}

struct MainTabsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView {
            HomeView(viewModel: HomeViewModel(environment: environment))
                .tabItem { Label("Home", systemImage: "power.circle.fill") }
            VPNView(viewModel: VPNViewModel(environment: environment))
                .tabItem { Label("VPN", systemImage: "qrcode") }
            ProfileView(viewModel: ProfileViewModel(environment: environment))
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(DS.blue)
    }
}

#Preview {
    RootView()
        .environmentObject(AppEnvironment.preview())
}
