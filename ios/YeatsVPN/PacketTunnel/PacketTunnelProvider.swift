import os.log
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "uz.yeats.vpn.PacketTunnel", category: "PacketTunnel")
    private var subscriptionURL: String?
    private var serverConfigs: [ParsedServer] = []

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let providerURL = (protocolConfiguration as? NETunnelProviderProtocol)?
            .providerConfiguration?["subscriptionUrl"] as? String
        let optionURL = options?["subscriptionUrl"] as? String
        subscriptionURL = optionURL ?? providerURL

        guard let subscriptionURL, URL(string: subscriptionURL) != nil else {
            logger.error("Missing or invalid subscription URL.")
            completionHandler(PacketTunnelError.missingSubscriptionURL)
            return
        }

        logger.info("Starting Yeats packet tunnel.")

        fetchSubscription(url: subscriptionURL) { [weak self] servers in
            guard let self else {
                completionHandler(PacketTunnelError.missingSubscriptionURL)
                return
            }
            self.serverConfigs = servers
            self.logger.info("Parsed \(servers.count) server(s) from subscription.")
            self.applyTunnelSettings(completionHandler: completionHandler)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Stopping Yeats packet tunnel, reason: \(reason.rawValue)")
        subscriptionURL = nil
        serverConfigs = []
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let completionHandler else { return }
        logger.info("Received app message.")
        let status = PacketTunnelStatus(
            isRunning: subscriptionURL != nil,
            subscriptionURL: subscriptionURL,
            serverCount: serverConfigs.count
        )
        let data = try? JSONEncoder().encode(status)
        completionHandler(data ?? messageData)
    }

    // MARK: - Tunnel Settings

    private func applyTunnelSettings(completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.255.0.1")

        let ipv4 = NEIPv4Settings(addresses: ["10.255.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        // Exclude the VPN server address(es) from the tunnel to prevent routing loops
        ipv4.excludedRoutes = serverConfigs.compactMap { server in
            guard !server.address.isEmpty else { return nil }
            return NEIPv4Route(destinationAddress: server.address, subnetMask: "255.255.255.255")
        }
        settings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(addresses: ["fd00::2"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "1.0.0.1", "8.8.8.8"])
        settings.mtu = NSNumber(value: 1400)

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                self?.logger.error("Failed to apply tunnel settings: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
                return
            }
            self?.logger.info("Tunnel settings applied. VPN active.")
            self?.startReadingPackets()
            completionHandler(nil)
        }
    }

    // MARK: - Packet Processing

    private func startReadingPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            self?.handlePackets(packets, protocols: protocols)
            self?.startReadingPackets()
        }
    }

    private func handlePackets(_ packets: [Data], protocols: [NSNumber]) {
        // Forward packets back through the tunnel.
        // When a VPN core (sing-box, Xray) is integrated, packets would be
        // encrypted and sent to the proxy server here instead.
        packetFlow.writePackets(packets, withProtocols: protocols)
    }

    // MARK: - Subscription Fetch

    private func fetchSubscription(url: String, completion: @escaping ([ParsedServer]) -> Void) {
        guard let subURL = URL(string: url) else {
            completion([])
            return
        }
        let task = URLSession.shared.dataTask(with: subURL) { [weak self] data, _, error in
            guard let self else {
                completion([])
                return
            }
            guard let data, error == nil, let raw = String(data: data, encoding: .utf8) else {
                self.logger.warning("Failed to fetch subscription: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                completion([])
                return
            }
            let decoded: String
            if let b64Data = Data(base64Encoded: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
               let str = String(data: b64Data, encoding: .utf8) {
                decoded = str
            } else {
                decoded = raw
            }
            let servers = decoded.components(separatedBy: .newlines).compactMap { line -> ParsedServer? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let url = URL(string: trimmed), let host = url.host else { return nil }
                return ParsedServer(address: host, port: url.port ?? 443, scheme: url.scheme ?? "unknown")
            }
            self.logger.info("Subscription decoded: \(servers.count) server(s)")
            completion(servers)
        }
        task.resume()
    }
}

// MARK: - Types

private struct ParsedServer {
    let address: String
    let port: Int
    let scheme: String
}

private struct PacketTunnelStatus: Encodable {
    let isRunning: Bool
    let subscriptionURL: String?
    let serverCount: Int
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
