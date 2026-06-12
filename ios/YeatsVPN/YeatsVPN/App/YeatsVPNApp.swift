import SwiftUI

@main
struct YeatsVPNApp: App {
    @StateObject private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .preferredColorScheme(nil)
        }
    }
}
