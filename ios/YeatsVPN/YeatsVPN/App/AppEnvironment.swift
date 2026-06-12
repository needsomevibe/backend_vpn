import Foundation
import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var route: AppRoute = .splash
    @Published var currentUser: UserProfile?
    @Published var vpnProfile: VPNProfile?
    @Published var isOffline = false
    let debugLog: DebugLogStore

    let authService: AuthServicing
    let vpnService: VPNServicing
    let tokenStore: TokenStoring
    let connectivity: ConnectivityMonitoring
    let storeKit: StoreKitManaging
    let push: PushNotificationManaging
    let networkExtension: NetworkExtensionManaging

    init(
        authService: AuthServicing,
        vpnService: VPNServicing,
        tokenStore: TokenStoring,
        debugLog: DebugLogStore,
        connectivity: ConnectivityMonitoring,
        storeKit: StoreKitManaging,
        push: PushNotificationManaging,
        networkExtension: NetworkExtensionManaging
    ) {
        self.authService = authService
        self.vpnService = vpnService
        self.tokenStore = tokenStore
        self.debugLog = debugLog
        self.connectivity = connectivity
        self.storeKit = storeKit
        self.push = push
        self.networkExtension = networkExtension
    }

    static func live() -> AppEnvironment {
        let keychain = KeychainService()
        let tokenStore = TokenStore(keychain: keychain)
        let apiClient = APIClient(baseURL: URL(string: "https://api.yeats.uz")!, tokenStore: tokenStore)
        let authService = AuthService(apiClient: apiClient, tokenStore: tokenStore)
        let vpnService = VPNService(apiClient: apiClient)
        let debugLog = DebugLogStore()
        apiClient.authRefresher = authService
        return AppEnvironment(
            authService: authService,
            vpnService: vpnService,
            tokenStore: tokenStore,
            debugLog: debugLog,
            connectivity: ConnectivityMonitor(),
            storeKit: PlaceholderStoreKitManager(),
            push: PlaceholderPushNotificationManager(),
            networkExtension: AppleVPNManager(debugLog: debugLog)
        )
    }

    func bootstrap() async {
        debugLog.info("Bootstrap started")
        isOffline = !connectivity.isOnline
        guard await tokenStore.hasRefreshToken() else {
            debugLog.info("No refresh token; routing to login")
            route = .login
            return
        }
        do {
            debugLog.info("Refreshing stored session")
            _ = try await authService.refreshSession()
            async let user = authService.me()
            async let vpn = vpnService.profile()
            currentUser = try await user
            vpnProfile = try await vpn
            debugLog.info("Session restored")
            route = .main
        } catch {
            debugLog.error("Bootstrap failed: \(error.localizedDescription)")
            await tokenStore.clear()
            route = .login
        }
    }

    func handleAuthenticated(_ response: AuthResponse) {
        currentUser = response.user
        vpnProfile = response.user.effectiveVPN.map { VPNProfile(account: $0) }
        route = .main
    }

    func logout() async {
        await authService.logout()
        currentUser = nil
        vpnProfile = nil
        route = .login
    }
}
