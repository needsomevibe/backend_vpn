import os.log
import NetworkExtension
import Libbox

final class PacketTunnelProvider: NEPacketTunnelProvider {
private let logger = Logger(subsystem: "uz.yeats.vpn.PacketTunnel", category: "PacketTunnel")
private var subscriptionURL: String?
private var boxService: LibboxCommandServer?

override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
    let providerURL = (protocolConfiguration as? NETunnelProviderProtocol)?
        .providerConfiguration?["subscriptionUrl"] as? String
    let optionURL = options?["subscriptionUrl"] as? String
    subscriptionURL = optionURL ?? providerURL

    guard let subscriptionURL, let url = URL(string: subscriptionURL) else {
        completionHandler(PacketTunnelError.missingSubscriptionURL)
        return
    }

    Task {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let rawSubscription = String(data: data, encoding: .utf8) else {
                throw PacketTunnelError.invalidSubscriptionData
            }

            let config = SingBoxConfigBuilder.build(from: rawSubscription)

            // 1. Setup Network Settings
            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "172.19.0.1")

            let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
            ipv4.includedRoutes = [NEIPv4Route.default()]
            settings.ipv4Settings = ipv4

            let ipv6 = NEIPv6Settings(addresses: ["fdfe:dcba:9876::1"], networkPrefixLengths: [126])
            ipv6.includedRoutes = [NEIPv6Route.default()]
            settings.ipv6Settings = ipv6

            settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
            settings.mtu = 1500

            try await setTunnelNetworkSettings(settings)

            // 2. Start Sing-Box
            let box = LibboxNewCommandServer(self, self, nil)
            try box?.startOrReloadService(config, options: nil)
            self.boxService = box

            logger.info("VPN started successfully with Sing-Box integration")
            completionHandler(nil)
        } catch {
            logger.error("Failed to start VPN: \(error.localizedDescription, privacy: .public)")
            completionHandler(error)
        }
    }
}

override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    logger.info("Stopping tunnel, reason: \(reason.rawValue)")
    boxService?.close()
    boxService = nil
    subscriptionURL = nil
    completionHandler()
}

override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
    guard let completionHandler else { return }

    let status = PacketTunnelStatus(
        isRunning: subscriptionURL != nil,
        subscriptionURL: subscriptionURL
    )

    let data = try? JSONEncoder().encode(status)
    completionHandler(data ?? messageData)
}

}

private struct PacketTunnelStatus: Encodable {
let isRunning: Bool
let subscriptionURL: String?
}

private enum PacketTunnelError: LocalizedError {
case missingSubscriptionURL
case invalidSubscriptionData

var errorDescription: String? {
    switch self {
    case .missingSubscriptionURL:
        return "Missing VPN subscription URL."
    case .invalidSubscriptionData:
        return "Failed to download or decode subscription data."
    }
}

}

// MARK: - Libbox Protocols

extension PacketTunnelProvider: LibboxCommandServerHandler {
    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus? { nil }
    func serviceReload() throws -> Bool { true }
    func serviceStop() throws -> Bool { true }
    func setSystemProxyEnabled(_ enabled: Bool) throws -> Bool { true }
    func writeDebugMessage(_ message: String?) {
        if let message { logger.debug("\(message, privacy: .public)") }
    }
}

extension PacketTunnelProvider: LibboxPlatformInterface {
    func autoDetectInterfaceControl(_ fd: Int32) throws -> Bool { true }
    func clearDNSCache() {}
    func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListener?) throws -> Bool { true }
    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32, destinationAddress: String?, destinationPort: Int32) throws -> LibboxConnectionOwner? { nil }
    func getInterfaces() throws -> LibboxNetworkInterfaceIterator? { nil }
    func includeAllNetworks() -> Bool { true }
    func localDNSTransport() -> LibboxLocalDNSTransport? { nil }
    func openTun(_ options: LibboxTunOptions?, ret0_: UnsafeMutablePointer<Int32>?) throws -> Bool {
        // Libbox handles TUN internally when auto_route is true in config.
        // We return the FD from packetFlow if needed, but sing-box usually takes it.
        // On iOS NE, we don't always need to pass FD if we use sing-box's internal TUN.
        true
    }
    func readWIFIState() -> LibboxWIFIState? { nil }
    func sendNotification(_ notification: LibboxNotification?) throws -> Bool { true }
    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListener?) throws -> Bool { true }
    func systemCertificates() -> LibboxStringIterator? { nil }
    func underNetworkExtension() -> Bool { true }
    func usePlatformAutoDetectInterfaceControl() -> Bool { false }
    func useProcFS() -> Bool { false }
}
