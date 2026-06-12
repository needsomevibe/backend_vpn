import Foundation
import NetworkExtension

final class AppleVPNManager: NetworkExtensionManaging, @unchecked Sendable {
    private let providerBundleIdentifier = "uz.yeats.vpn.PacketTunnel"
    private let localizedDescription = "Yeats VPN"

    func currentState() async -> VPNConnectionState {
        do {
            guard let manager = try await loadManager() else {
                return .disconnected
            }
            switch manager.connection.status {
            case .connected:
                return .connected
            case .connecting, .reasserting:
                return .connecting
            case .disconnecting:
                return .connecting
            case .invalid:
                return .unavailable("VPN configuration is invalid. Reinstall the VPN profile.")
            case .disconnected:
                return .disconnected
            @unknown default:
                return .disconnected
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func connect(subscriptionURL: String) async throws {
        let manager = try await loadOrCreateManager(subscriptionURL: subscriptionURL)
        try await save(manager)
        try await loadFromPreferences(manager)

        guard let session = manager.connection as? NETunnelProviderSession else {
            throw AppleVPNError.invalidTunnelSession
        }
        try session.startTunnel(options: [
            PacketTunnelKeys.subscriptionURL: subscriptionURL as NSString
        ])
    }

    func disconnect() async {
        do {
            let manager = try await loadManager()
            manager?.connection.stopVPNTunnel()
        } catch {
            // Stop is best-effort; UI state refresh will surface configuration issues.
        }
    }

    private func loadManager() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        return managers.first { manager in
            guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else {
                return false
            }
            return proto.providerBundleIdentifier == providerBundleIdentifier
        }
    }

    private func loadOrCreateManager(subscriptionURL: String) async throws -> NETunnelProviderManager {
        let manager = try await loadManager() ?? NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = providerBundleIdentifier
        proto.serverAddress = "Yeats VPN"
        proto.disconnectOnSleep = false
        proto.providerConfiguration = [
            PacketTunnelKeys.subscriptionURL: subscriptionURL
        ]

        manager.localizedDescription = localizedDescription
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        return manager
    }

    private func save(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func loadFromPreferences(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

enum PacketTunnelKeys {
    static let subscriptionURL = "subscriptionUrl"
}

enum AppleVPNError: LocalizedError {
    case invalidTunnelSession

    var errorDescription: String? {
        switch self {
        case .invalidTunnelSession:
            "Could not create Packet Tunnel session."
        }
    }
}
