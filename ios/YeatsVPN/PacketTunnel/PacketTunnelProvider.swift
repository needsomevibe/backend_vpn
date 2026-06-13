import os.log
import NetworkExtension
#if canImport(Libbox)
import Libbox
#endif

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "uz.yeats.vpn.PacketTunnel", category: "PacketTunnel")
    private var subscriptionURL: String?
    private var rawSubscription: String?

    #if canImport(Libbox)
    private var boxService: LibboxBoxService?
    private var commandServer: LibboxCommandServer?
    #endif

    // MARK: - Tunnel Lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
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

        fetchSubscription(url: subscriptionURL) { [weak self] decoded in
            guard let self, !decoded.isEmpty else {
                completionHandler(PacketTunnelError.emptySubscription)
                return
            }
            self.rawSubscription = decoded
            self.logger.info("Subscription fetched, building sing-box config.")

            #if canImport(Libbox)
            self.startSingBox(rawSubscription: decoded, completionHandler: completionHandler)
            #else
            self.logger.warning("Libbox not available — running in passthrough mode (no proxy).")
            self.applyFallbackTunnelSettings(completionHandler: completionHandler)
            #endif
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Stopping Yeats packet tunnel, reason: \(reason.rawValue)")

        #if canImport(Libbox)
        stopSingBox()
        #endif

        subscriptionURL = nil
        rawSubscription = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let completionHandler else { return }

        var isRunning = subscriptionURL != nil
        #if canImport(Libbox)
        isRunning = boxService != nil
        #endif

        let status = PacketTunnelStatus(isRunning: isRunning, subscriptionURL: subscriptionURL)
        let data = try? JSONEncoder().encode(status)
        completionHandler(data ?? messageData)
    }

    // MARK: - Sing-Box Integration

    #if canImport(Libbox)
    private func startSingBox(rawSubscription: String, completionHandler: @escaping (Error?) -> Void) {
        let selectedIndex = (protocolConfiguration as? NETunnelProviderProtocol)?
            .providerConfiguration?["selectedServerIndex"] as? Int ?? 0

        let configJSON = SingBoxConfigBuilder.build(from: rawSubscription, selectedIndex: selectedIndex)

        guard configJSON != "{}" else {
            logger.error("Failed to generate sing-box config — no valid outbounds.")
            completionHandler(PacketTunnelError.configGenFailed)
            return
        }

        logger.info("Sing-box config generated. Starting service.")

        do {
            setupLibboxPaths()

            let service = try LibboxNewService(configJSON, self)
            try service.start()
            self.boxService = service

            logger.info("Sing-box service started successfully.")
            completionHandler(nil)
        } catch {
            logger.error("Failed to start sing-box: \(error.localizedDescription, privacy: .public)")
            completionHandler(error)
        }
    }

    private func stopSingBox() {
        do {
            try boxService?.close()
        } catch {
            logger.error("Failed to close sing-box: \(error.localizedDescription, privacy: .public)")
        }
        boxService = nil
        commandServer?.close()
        commandServer = nil
    }

    private func setupLibboxPaths() {
        let basePath = sharedContainerPath()
        let workDir = basePath + "/sing-box"
        let tmpDir = basePath + "/sing-box/tmp"

        for dir in [workDir, tmpDir] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        LibboxSetup(workDir, workDir, tmpDir, false)
        LibboxRedirectStderr(workDir + "/stderr.log", nil)
    }
    #endif

    private func sharedContainerPath() -> String {
        let groupID = "group.uz.yeats.vpn"
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return url.path
        }
        return NSTemporaryDirectory()
    }

    // MARK: - Fallback (no Libbox)

    private func applyFallbackTunnelSettings(completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.255.0.1")

        let ipv4 = NEIPv4Settings(addresses: ["10.255.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
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
            self?.logger.info("Fallback tunnel settings applied (no proxy engine).")
            completionHandler(nil)
        }
    }

    // MARK: - TUN File Descriptor

    private func findTunnelFileDescriptor() -> Int32? {
        var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        for fd: Int32 in 0...1024 {
            var len = socklen_t(buf.count)
            if getsockopt(fd, 2 /* SYSPROTO_CONTROL */, 2 /* UTUN_OPT_IFNAME */, &buf, &len) == 0 {
                let name = String(cString: buf)
                if name.hasPrefix("utun") {
                    return fd
                }
            }
        }
        return nil
    }

    // MARK: - Subscription Fetch

    private func fetchSubscription(url: String, completion: @escaping (String) -> Void) {
        guard let subURL = URL(string: url) else {
            completion("")
            return
        }
        let task = URLSession.shared.dataTask(with: subURL) { [weak self] data, _, error in
            guard let self else {
                completion("")
                return
            }
            guard let data, error == nil, let raw = String(data: data, encoding: .utf8) else {
                self.logger.warning("Failed to fetch subscription: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                completion("")
                return
            }

            let decoded: String
            if let b64Data = Data(base64Encoded: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
               let str = String(data: b64Data, encoding: .utf8) {
                decoded = str
            } else {
                decoded = raw
            }

            let lineCount = decoded.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .count
            self.logger.info("Subscription decoded: \(lineCount) line(s)")
            completion(decoded)
        }
        task.resume()
    }

    // MARK: - Helpers

    private func parseCIDR(_ cidr: String) -> (String, Int) {
        let parts = cidr.components(separatedBy: "/")
        let address = parts[0]
        let prefix = parts.count > 1 ? Int(parts[1]) ?? 32 : 32
        return (address, prefix)
    }

    private func prefixToMask(_ prefix: Int) -> String {
        let mask = prefix > 0 ? UInt32.max << (32 - prefix) : 0
        return "\(mask >> 24 & 0xFF).\(mask >> 16 & 0xFF).\(mask >> 8 & 0xFF).\(mask & 0xFF)"
    }
}

// MARK: - LibboxPlatformInterface

#if canImport(Libbox)
extension PacketTunnelProvider: LibboxPlatformInterface {

    func usePlatformAutoDetectInterfaceControl() -> Bool {
        true
    }

    func autoDetectInterfaceControl(_ fd: Int32) throws {
        // Mark the socket for direct internet access (bypass tunnel)
    }

    func openTun(_ options: LibboxTunOptions?) throws -> Int32 {
        logger.info("Libbox requested TUN interface.")

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.255.0.1")

        // IPv4
        let inet4Addresses = options?.getInet4Address()
        let inet4Addr = inet4Addresses?.next() ?? "172.19.0.1/30"
        let (addr4, prefix4) = parseCIDR(inet4Addr)
        let mask4 = prefixToMask(prefix4)
        let ipv4 = NEIPv4Settings(addresses: [addr4], subnetMasks: [mask4])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        // IPv6
        let inet6Addresses = options?.getInet6Address()
        let inet6Addr = inet6Addresses?.next() ?? "fdfe:dcba:9876::1/126"
        let (addr6, prefix6) = parseCIDR(inet6Addr)
        let ipv6 = NEIPv6Settings(addresses: [addr6], networkPrefixLengths: [NSNumber(value: prefix6)])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        // DNS
        let dnsAddr = options?.dnsServerAddress ?? "1.1.1.1"
        settings.dnsSettings = NEDNSSettings(servers: dnsAddr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })

        // MTU
        let mtu = options?.mtu ?? 9000
        settings.mtu = NSNumber(value: mtu)

        // Apply settings synchronously using a semaphore
        let sem = DispatchSemaphore(value: 0)
        var settingsError: Error?

        setTunnelNetworkSettings(settings) { error in
            settingsError = error
            sem.signal()
        }
        sem.wait()

        if let err = settingsError {
            logger.error("Failed to apply tunnel settings: \(err.localizedDescription, privacy: .public)")
            throw err
        }

        logger.info("Tunnel settings applied. Looking for TUN fd.")

        guard let fd = findTunnelFileDescriptor() else {
            logger.error("Could not find TUN file descriptor.")
            throw PacketTunnelError.tunFdNotFound
        }

        logger.info("Found TUN fd: \(fd)")
        return fd
    }

    func writeLog(_ message: String?) {
        guard let message else { return }
        logger.info("[sing-box] \(message, privacy: .public)")
    }

    func useProcFS() -> Bool {
        false
    }

    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32, destinationAddress: String?, destinationPort: Int32) throws -> Int32 {
        -1
    }

    func packageName(byUID uid: Int32) throws -> String {
        ""
    }

    func uid(byPackageName packageName: String?) throws -> Int32 {
        -1
    }

    func sendNotification(_ notification: LibboxNotification?) throws {
        // No-op for now
    }

    func clearDNSCache() {
        // No-op
    }

    func readWIFIState() -> LibboxWIFIState? {
        nil
    }

    func writeMemoryLimitWarning(_ memoryLimit: Int64) {
        logger.warning("Memory limit warning: \(memoryLimit)")
    }
}
#endif

// MARK: - Types

private struct PacketTunnelStatus: Encodable {
    let isRunning: Bool
    let subscriptionURL: String?
}

private enum PacketTunnelError: LocalizedError {
    case missingSubscriptionURL
    case emptySubscription
    case configGenFailed
    case tunFdNotFound

    var errorDescription: String? {
        switch self {
        case .missingSubscriptionURL: return "Missing VPN subscription URL."
        case .emptySubscription: return "Subscription returned no servers."
        case .configGenFailed: return "Failed to generate VPN configuration."
        case .tunFdNotFound: return "Could not find TUN file descriptor."
        }
    }
}
