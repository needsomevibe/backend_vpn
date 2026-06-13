import Foundation

#if DEBUG
extension AppEnvironment {
    static func preview() -> AppEnvironment {
        let tokenStore = InMemoryTokenStore()
        let auth = PreviewAuthService()
        let vpn = PreviewVPNService()
        let environment = AppEnvironment(
            authService: auth,
            vpnService: vpn,
            tokenStore: tokenStore,
            debugLog: DebugLogStore(),
            connectivity: PreviewConnectivityMonitor(),
            storeKit: PlaceholderStoreKitManager(),
            push: PlaceholderPushNotificationManager(),
            networkExtension: PlaceholderNetworkExtensionManager()
        )
        environment.route = .main
        environment.currentUser = PreviewData.user
        environment.vpnProfile = PreviewData.vpnProfile
        environment.servers = PreviewData.servers
        return environment
    }
}

enum PreviewData {
    static let vpnProfile = VPNProfile(
        status: "active",
        subscriptionUrl: "https://sub.yeats.uz/demo",
        trafficUsedGb: 12.4,
        trafficLimitGb: 100,
        expiresAt: Date().addingTimeInterval(2_592_000),
        nodeLocation: "US"
    )

    static let user = UserProfile(
        id: UUID().uuidString,
        email: "user@example.com",
        status: "ACTIVE",
        createdAt: Date(),
        vpn: VPNAccount(
            id: UUID().uuidString,
            remnawaveUuid: UUID().uuidString,
            remnawaveShortUuid: "demo",
            username: "user_demo",
            status: "ACTIVE",
            trafficLimitBytes: "107374182400",
            usedTrafficBytes: "13314398617",
            expiresAt: Date().addingTimeInterval(2_592_000),
            subscriptionUrl: "https://sub.yeats.uz/demo"
        ),
        vpnAccount: nil,
        subscription: Subscription(
            id: UUID().uuidString,
            status: "TRIALING",
            expiresAt: Date().addingTimeInterval(2_592_000),
            provider: "internal",
            plan: Plan(id: UUID().uuidString, name: "Free", trafficLimitGb: 100, deviceLimit: 1, durationDays: 30, priceCents: 0, currency: "USD")
        ),
        devices: [
            Device(id: UUID().uuidString, deviceId: "preview-device", platform: "ios", name: "iPhone 15 Pro", lastSeenAt: Date())
        ]
    )

    static let servers: [ServerConfig] = [
        ServerConfig(id: "1", name: "US East", address: "us1.yeats.uz", port: 443, proto: .vless, rawURI: "vless://demo@us1.yeats.uz:443#US%20East", countryCode: "US"),
        ServerConfig(id: "2", name: "Germany Frankfurt", address: "de1.yeats.uz", port: 443, proto: .vless, rawURI: "vless://demo@de1.yeats.uz:443#Germany%20Frankfurt", countryCode: "DE"),
        ServerConfig(id: "3", name: "Netherlands", address: "nl1.yeats.uz", port: 443, proto: .trojan, rawURI: "trojan://demo@nl1.yeats.uz:443#Netherlands", countryCode: "NL"),
    ]
}

actor InMemoryTokenStore: TokenStoring {
    var access: String?
    var refresh: String?
    func accessToken() async -> String? { access }
    func refreshToken() async -> String? { refresh }
    func save(accessToken: String, refreshToken: String) async throws {
        access = accessToken
        refresh = refreshToken
    }
    func clear() async {
        access = nil
        refresh = nil
    }
    func hasRefreshToken() async -> Bool { refresh != nil }
}

final class PreviewConnectivityMonitor: ConnectivityMonitoring {
    let isOnline = true
}

final class PreviewAuthService: AuthServicing, @unchecked Sendable {
    func register(email: String, password: String) async throws -> AuthResponse { AuthResponse(accessToken: "access", refreshToken: "refresh", user: PreviewData.user) }
    func login(email: String, password: String) async throws -> AuthResponse { AuthResponse(accessToken: "access", refreshToken: "refresh", user: PreviewData.user) }
    func loginWithApple(identityToken: String, authorizationCode: String?, fullName: String?) async throws -> AuthResponse { AuthResponse(accessToken: "access", refreshToken: "refresh", user: PreviewData.user) }
    func refreshSession() async throws -> AuthResponse { AuthResponse(accessToken: "access", refreshToken: "refresh", user: PreviewData.user) }
    func me() async throws -> UserProfile { PreviewData.user }
    func logout() async {}
}

struct PreviewVPNService: VPNServicing {
    func profile() async throws -> VPNProfile { PreviewData.vpnProfile }
    func usage() async throws -> VPNUsage {
        VPNUsage(usedTrafficBytes: "13314398617", usedTrafficGb: 12.4, trafficLimitBytes: "107374182400", trafficLimitGb: 100, nodeLocation: "US")
    }
    func enable() async throws -> VPNToggleResponse { VPNToggleResponse(id: nil, status: "ACTIVE", success: true) }
    func disable() async throws -> VPNToggleResponse { VPNToggleResponse(id: nil, status: "DISABLED", success: true) }
    func resetTraffic() async throws -> VPNResetTrafficResponse { VPNResetTrafficResponse(success: true) }
    func regenerateSubscription() async throws -> VPNRegenerateResponse { VPNRegenerateResponse(subscriptionUrl: "https://sub.yeats.uz/new-demo") }
    func plans() async throws -> [Plan] {
        [Plan(id: UUID().uuidString, name: "Free", trafficLimitGb: 100, deviceLimit: 1, durationDays: 30, priceCents: 0, currency: "USD")]
    }
}
#endif
