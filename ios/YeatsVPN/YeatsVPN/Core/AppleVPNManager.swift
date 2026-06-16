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
        await logInfo("PacketTunnel bundle id: \(providerBundleIdentifier)")

        // Don't restart if tunnel is already active
        if let existing = try? await loadManager(),
           existing.connection.status == .connected || existing.connection.status == .connecting {
            await logInfo("Tunnel already active (status \(existing.connection.status.rawValue)), skipping reconnect")
            return
        }

        SharedDiagnostics.clearPhase()
        await importExtensionDiagnostics(includeStatus: true)
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
        await observeStartup(session)
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

    private func pingProvider(_ session: NETunnelProviderSession) async -> PacketTunnelProviderStatus? {
        do {
            let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                do {
                    try session.sendProviderMessage(Data("status".utf8)) { response in
                        continuation.resume(returning: response)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            guard let data, !data.isEmpty else {
                await logInfo("PacketTunnel provider responded with empty message (extension may still be starting or crashed)")
                return nil
            }

            if let status = try? JSONDecoder().decode(PacketTunnelProviderStatus.self, from: data) {
                await logInfo("PacketTunnel provider responded: running=\(status.isRunning), phase=\(status.startupPhase ?? "unknown"), error=\(status.lastError ?? "none")")
                for line in status.logs.suffix(20) {
                    await logInfo("PacketTunnel live: \(line)")
                }
                return status
            } else if let response = String(data: data, encoding: .utf8) {
                await logInfo("PacketTunnel provider responded (non-JSON): \(response)")
            } else {
                await logInfo("PacketTunnel provider responded with \(data.count) bytes (not decodable)")
            }
            return nil
        } catch {
            await logError("PacketTunnel provider did not respond: \(error.localizedDescription)")
            return nil
        }
    }

    private func observeStartup(_ session: NETunnelProviderSession) async {
        // Wait 2s before first ping to give extension time to download subscription and start libbox
        try? await Task.sleep(for: .seconds(2))
        await logInfo("Startup status after 2s: \(session.status.rawValue)")
        await importExtensionDiagnostics(includeStatus: true)

        if session.status == .disconnected || session.status == .invalid {
            await logError("PacketTunnel stopped during startup with status \(session.status.rawValue)")
            await logLastDisconnectError(session)
            await logCrashPhase()
            await importExtensionDiagnostics(includeStatus: true)
            return
        }

        for attempt in 1...8 {
            if session.status == .connected || session.status == .connecting {
                let status = await pingProvider(session)
                if let status {
                    if status.isRunning {
                        await logInfo("PacketTunnel confirmed running after \(attempt) ping(s)")
                        return
                    }
                    if status.startupPhase == "failed" {
                        await logError("PacketTunnel startup failed: \(status.lastError ?? "unknown error")")
                        await importExtensionDiagnostics(includeStatus: true)
                        return
                    }
                    // Extension is still starting — wait and retry
                    await logInfo("PacketTunnel still starting (phase: \(status.startupPhase ?? "unknown")), waiting...")
                }
            }

            if session.status == .disconnected || session.status == .invalid {
                await logError("PacketTunnel stopped during startup with status \(session.status.rawValue)")
                await logLastDisconnectError(session)
                await logCrashPhase()
                await importExtensionDiagnostics(includeStatus: true)
                return
            }

            try? await Task.sleep(for: .seconds(1))
            await logInfo("Startup poll \(attempt + 1): NE status \(session.status.rawValue)")
        }

        await logInfo("Startup observation timed out — extension status: \(session.status.rawValue)")
        await importExtensionDiagnostics(includeStatus: true)
    }

    private func logCrashPhase() async {
        if let phase = SharedDiagnostics.readPhase() {
            await logError("Extension last known phase: \(phase.phase), error: \(phase.error ?? "none"), at: \(phase.timestamp)")
        } else {
            await logError("Extension phase file not found — App Group may not be provisioned or extension never started")
        }
    }

    private func logLastDisconnectError(_ session: NETunnelProviderSession) async {
        guard #available(iOS 16.0, *) else { return }
        let error = await withCheckedContinuation { (continuation: CheckedContinuation<Error?, Never>) in
            session.fetchLastDisconnectError { error in
                continuation.resume(returning: error)
            }
        }

        if let error {
            let nsError = error as NSError
            await logError("Last VPN disconnect error: \(nsError.domain) code \(nsError.code) - \(nsError.localizedDescription)")
        } else {
            await logInfo("Last VPN disconnect error: none")
        }
    }

    private func importExtensionDiagnostics(includeStatus: Bool) async {
        await MainActor.run {
            debugLog?.importExtensionLogs(includeStatus: includeStatus)
        }
    }

    @MainActor
    private func logInfo(_ message: String) {
        if let debugLog {
            debugLog.info(message)
        } else {
            logger.info("\(message, privacy: .public)")
        }
    }

    @MainActor
    private func logError(_ message: String) {
        if let debugLog {
            debugLog.error(message)
        } else {
            logger.error("\(message, privacy: .public)")
        }
    }
}

enum PacketTunnelKeys {
    static let subscriptionURL = "subscriptionUrl"
}

private struct PacketTunnelProviderStatus: Decodable {
    let isRunning: Bool
    let startupPhase: String?
    let lastError: String?
    let subscriptionURL: String?
    let logs: [String]
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
