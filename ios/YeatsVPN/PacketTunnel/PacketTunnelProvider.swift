import os.log
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
private let logger = Logger(subsystem: "uz.yeats.vpn.PacketTunnel", category: "PacketTunnel")
private var subscriptionURL: String?


override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
    let providerURL = (protocolConfiguration as? NETunnelProviderProtocol)?
        .providerConfiguration?["subscriptionUrl"] as? String
    let optionURL = options?["subscriptionUrl"] as? String
    subscriptionURL = optionURL ?? providerURL

    guard subscriptionURL != nil else {
        completionHandler(PacketTunnelError.missingSubscriptionURL)
        return
    }

    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.255.0.1")

    let ipv4 = NEIPv4Settings(
        addresses: ["10.255.0.2"],
        subnetMasks: ["255.255.255.0"]
    )

    // IMPORTANT:
    // Keep routes empty until real sing-box/libbox integration is added.
    // This avoids breaking all phone traffic.
    ipv4.includedRoutes = []

    settings.ipv4Settings = ipv4
    settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
    settings.mtu = NSNumber(value: 1400)

    setTunnelNetworkSettings(settings) { [weak self] error in
        if let error {
            self?.logger.error("Failed to apply tunnel settings: \(error.localizedDescription, privacy: .public)")
            completionHandler(error)
            return
        }

        self?.logger.info("PacketTunnel started in safe mode. Libbox integration is not active yet.")
        completionHandler(nil)
    }
}

override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    logger.info("Stopping tunnel, reason: \(reason.rawValue)")
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

var errorDescription: String? {
    switch self {
    case .missingSubscriptionURL:
        return "Missing VPN subscription URL."
    }
}

}
