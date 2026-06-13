import Foundation
import NetworkExtension
import os.log

final class AppleVPNManager: NetworkExtensionManaging, @unchecked Sendable {
    private let providerBundleIdentifier = "uz.yeats.vpn.PacketTunnel"
    private let localizedDescription = "Yeats VPN"
    private let logger = Logger(subsystem: "uz.yeats.vpn", category: "AppleVPNManager")
    private let debugLog: DebugLogStore?
    private var statusObserver: NSObjectProtocol?

    var onStateChange: (@Sendable (VPNConnectionState) -> Void)?

    init(debugLog: DebugLogStore? = nil) {
        self.debugLog = debugLog
        startObservingStatus()
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }

    func currentState() async -> VPNConnectionState {
        do {
            await logInfo("Loading VPN state")
            guard let manager = try await loadManager() else {
                await logInfo("No saved VPN configuration")
                return .disconnected
            }
            await logInfo("Current NE status: \(manager.connection.status.rawValue)")
            return mapStatus(manager.connection.status)
        } catch {
            await logError("Failed to load VPN state: \(error.localizedDescription)")
            return .unavailable(error.localizedDescription)
        }
    }

    func connect(subscriptionURL: String) async throws {
        await logInfo("Connect requested")
        await logInfo("Loading or creating NETunnelProviderManager")
        let manager = try await loadOrCreateManager(subscriptionURL: subscriptionURL)
        await logInfo("Saving VPN configuration")
        try await save(manager)
        await logInfo("Saved VPN configuration")
        await logInfo("Reloading VPN configuration")
        try await loadFromPreferences(manager)
        await logInfo("Reloaded VPN configuration")

        guard let session = manager.connection as? NETunnelProviderSession else {
            await logError("manager.connection is not NETunnelProviderSession")
            throw AppleVPNError.invalidTunnelSession
        }
        await logInfo("Starting PacketTunnel session")
        try session.startTunnel(options: [
            PacketTunnelKeys.subscriptionURL: subscriptionURL as NSString
        ])
        await logInfo("startTunnel returned without throwing")
    }

    func disconnect() async {
        do {
            await logInfo("Disconnect requested")
            let manager = try await loadManager()
            manager?.connection.stopVPNTunnel()
            await logInfo("stopVPNTunnel called")
        } catch {
            await logError("Disconnect failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Status Observation

    private func startObservingStatus() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else { return }
            let state = self?.mapStatus(connection.status) ?? .disconnected
            self?.onStateChange?(state)
        }
    }

    private func mapStatus(_ status: NEVPNStatus) -> VPNConnectionState {
        switch status {
        case .connected:
            return .connected
        case .connecting, .reasserting:
            return .connecting
        case .disconnecting:
            return .disconnecting
        case .invalid:
            return .unavailable("VPN configuration is invalid. Reinstall the VPN profile.")
        case .disconnected:
            return .disconnected
        @unknown default:
            return .disconnected
        }
    }

    // MARK: - Manager Loading

    private func loadManager() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        await logInfo("Loaded \(managers.count) VPN manager(s) from preferences")
        return managers.first { manager in
            guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else {
                return false
            }
            return proto.providerBundleIdentifier == providerBundleIdentifier
        }
    }

    private func loadOrCreateManager(subscriptionURL: String) async throws -> NETunnelProviderManager {
        let manager = try await loadManager() ?? NETunnelProviderManager()
        await logInfo(manager.protocolConfiguration == nil ? "Creating new VPN manager" : "Updating existing VPN manager")
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
        manager.isOnDemandEnabled = false
        return manager
    }

    private func save(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    Task { await self.logError("saveToPreferences failed: \(error.localizedDescription)") }
                    continuation.resume(throwing: error)
                } else {
                    Task { await self.logInfo("saveToPreferences completed") }
                    continuation.resume()
                }
            }
        }
    }

    private func loadFromPreferences(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    Task { await self.logError("loadFromPreferences failed: \(error.localizedDescription)") }
                    continuation.resume(throwing: error)
                } else {
                    Task { await self.logInfo("loadFromPreferences completed") }
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func logInfo(_ message: String) {
        debugLog?.info(message)
        logger.info("\(message, privacy: .public)")
    }

    @MainActor
    private func logError(_ message: String) {
        debugLog?.error(message)
        logger.error("\(message, privacy: .public)")
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
