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
        devices: []
    )
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
}
#endif
