import Foundation

protocol StoreKitManaging: Sendable {
    func loadProducts() async
    func restorePurchases() async
}

struct PlaceholderStoreKitManager: StoreKitManaging {
    func loadProducts() async {}
    func restorePurchases() async {}
}

protocol PushNotificationManaging: Sendable {
    func registerForPushNotifications() async
}

struct PlaceholderPushNotificationManager: PushNotificationManaging {
    func registerForPushNotifications() async {}
}

enum VPNConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case unavailable(String)

    var isActive: Bool {
        self == .connected || self == .connecting
    }
}

protocol NetworkExtensionManaging: Sendable {
    func currentState() async -> VPNConnectionState
    /// The time the active tunnel was established, as tracked by the system.
    /// Survives app restarts while the tunnel keeps running.
    func connectedDate() async -> Date?
    func connect(subscriptionURL: String) async throws
    func refreshConfiguration(subscriptionURL: String) async throws
    func disconnect() async
}

struct PlaceholderNetworkExtensionManager: NetworkExtensionManaging {
    func currentState() async -> VPNConnectionState {
        .unavailable("In-app VPN requires NetworkExtension entitlement and provider implementation.")
    }

    func connectedDate() async -> Date? { nil }

    func connect(subscriptionURL: String) async throws {
        _ = subscriptionURL
    }

    func refreshConfiguration(subscriptionURL: String) async throws {
        _ = subscriptionURL
    }

    func disconnect() async {}
}
