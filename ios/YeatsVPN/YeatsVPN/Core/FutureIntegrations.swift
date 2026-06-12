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
    case unavailable(String)
}

protocol NetworkExtensionManaging: Sendable {
    func currentState() async -> VPNConnectionState
    func connect(subscriptionURL: String) async throws
    func disconnect() async
}

struct PlaceholderNetworkExtensionManager: NetworkExtensionManaging {
    func currentState() async -> VPNConnectionState {
        .unavailable("In-app VPN requires NetworkExtension entitlement and provider implementation.")
    }

    func connect(subscriptionURL: String) async throws {
        _ = subscriptionURL
    }

    func disconnect() async {}
}
