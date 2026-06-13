import Foundation
import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var route: AppRoute = .splash
    @Published var currentUser: UserProfile?
    @Published var vpnProfile: VPNProfile?
    @Published var isOffline = false
    @Published var connectionState: VPNConnectionState = .disconnected
    @Published var connectedSince: Date?
    @Published var servers: [ServerConfig] = []
    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }
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
        self.settings = Self.loadSettings()
    }

    static func live() -> AppEnvironment {
        let keychain = KeychainService()
        let tokenStore = TokenStore(keychain: keychain)
        let apiClient = APIClient(baseURL: URL(string: "https://api.yeats.uz")!, tokenStore: tokenStore)
        let authService = AuthService(apiClient: apiClient, tokenStore: tokenStore)
        let vpnService = VPNService(apiClient: apiClient)
        let debugLog = DebugLogStore()
        apiClient.authRefresher = authService
        let vpnManager = AppleVPNManager(debugLog: debugLog)
        let env = AppEnvironment(
            authService: authService,
            vpnService: vpnService,
            tokenStore: tokenStore,
            debugLog: debugLog,
            connectivity: ConnectivityMonitor(),
            storeKit: PlaceholderStoreKitManager(),
            push: PlaceholderPushNotificationManager(),
            networkExtension: vpnManager
        )
        vpnManager.onStateChange = { [weak env] state in
            Task { @MainActor in
                env?.connectionState = state
                if state == .connected && env?.connectedSince == nil {
                    env?.connectedSince = Date()
                } else if state == .disconnected || state == .disconnecting {
                    env?.connectedSince = nil
                }
            }
        }
        return env
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
            connectionState = await networkExtension.currentState()
            if connectionState == .connected {
                connectedSince = Date()
            }
            route = .main
            // Load server list in background
            Task { await loadServers() }
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
        Task { await loadServers() }
    }

    func logout() async {
        await authService.logout()
        if connectionState.isActive {
            await networkExtension.disconnect()
        }
        currentUser = nil
        vpnProfile = nil
        connectionState = .disconnected
        connectedSince = nil
        servers = []
        route = .login
    }

    func loadServers() async {
        guard let url = vpnProfile?.subscriptionUrl, !url.isEmpty else { return }
        do {
            let parsed = try await SubscriptionParser.fetchAndParse(subscriptionURL: url)
            servers = parsed
            debugLog.info("Loaded \(parsed.count) server(s)")
        } catch {
            debugLog.error("Failed to parse subscription: \(error.localizedDescription)")
        }
    }

    // MARK: - Settings Persistence

    private static let settingsKey = "yeats_app_settings"

    private static func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .default }
        return settings
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }
}
