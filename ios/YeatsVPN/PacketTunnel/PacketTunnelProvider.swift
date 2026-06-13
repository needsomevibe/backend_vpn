import os.log
import Network
import NetworkExtension
import Libbox

final class PacketTunnelProvider: NEPacketTunnelProvider {
private let logger = Logger(subsystem: "uz.yeats.vpn.PacketTunnel", category: "PacketTunnel")
private let appGroupIdentifier = "group.uz.yeats.vpn"
private let extensionLogFileName = "vpn-extension.log"
private var subscriptionURL: String?
private var boxService: LibboxCommandServer?
private var networkSettings: NEPacketTunnelNetworkSettings?
private var pathMonitor: NWPathMonitor?

override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
    let providerURL = (protocolConfiguration as? NETunnelProviderProtocol)?
        .providerConfiguration?["subscriptionUrl"] as? String
    let optionURL = options?["subscriptionUrl"] as? String
    subscriptionURL = optionURL ?? providerURL

    guard let subscriptionURL, let url = URL(string: subscriptionURL) else {
        logError("Missing subscription URL in provider configuration/options")
        completionHandler(PacketTunnelError.missingSubscriptionURL)
        return
    }

    Task {
        do {
            logInfo("PacketTunnel start requested")
            logInfo("Downloading subscription for tunnel startup")
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw PacketTunnelError.subscriptionHTTPStatus(http.statusCode)
            }
            guard let rawSubscription = String(data: data, encoding: .utf8) else {
                throw PacketTunnelError.invalidSubscriptionData
            }
            logInfo("Subscription downloaded, bytes: \(data.count)")

            let config = try SingBoxConfigBuilder.build(from: rawSubscription)
            logInfo("Generated sing-box config, bytes: \(config.utf8.count)")

            let box = LibboxNewCommandServer(self as LibboxCommandServerHandlerProtocol, self as LibboxPlatformInterfaceProtocol, nil)
            guard let box else {
                throw PacketTunnelError.libboxUnavailable
            }
            logInfo("Starting Libbox service")
            try box.startOrReloadService(config, options: nil)
            self.boxService = box

            logInfo("VPN started successfully with Sing-Box integration")
            completionHandler(nil)
        } catch {
            logError("Failed to start VPN: \(error.localizedDescription)")
            completionHandler(error)
        }
    }
}

override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    logInfo("Stopping tunnel, reason: \(reason.rawValue)")
    boxService?.close()
    boxService = nil
    pathMonitor?.cancel()
    pathMonitor = nil
    networkSettings = nil
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
case subscriptionHTTPStatus(Int)
case libboxUnavailable
case missingTunnelFileDescriptor
case connectionOwnerUnavailable
case defaultInterfaceMonitorUnavailable

var errorDescription: String? {
    switch self {
    case .missingSubscriptionURL:
        return "Missing VPN subscription URL."
    case .invalidSubscriptionData:
        return "Failed to download or decode subscription data."
    case .subscriptionHTTPStatus(let statusCode):
        return "Subscription server returned HTTP \(statusCode)."
    case .libboxUnavailable:
        return "Libbox command server is unavailable."
    case .missingTunnelFileDescriptor:
        return "Could not open the packet tunnel file descriptor."
    case .connectionOwnerUnavailable:
        return "Connection owner lookup is unavailable in the packet tunnel."
    case .defaultInterfaceMonitorUnavailable:
        return "Default interface monitor is not running."
    }
}

}

// MARK: - Libbox Protocols

extension PacketTunnelProvider: LibboxCommandServerHandlerProtocol {
    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        let status = LibboxSystemProxyStatus()
        guard let proxySettings = networkSettings?.proxySettings,
              proxySettings.httpServer != nil else {
            return status
        }
        status.available = true
        status.enabled = proxySettings.httpEnabled
        return status
    }

    func serviceReload() throws {}

    func serviceStop() throws {
        try boxService?.closeService()
    }

    func setSystemProxyEnabled(_ enabled: Bool) throws {
        guard let networkSettings,
              let proxySettings = networkSettings.proxySettings,
              proxySettings.httpServer != nil else {
            return
        }
        proxySettings.httpEnabled = enabled
        proxySettings.httpsEnabled = enabled
        networkSettings.proxySettings = proxySettings
        self.networkSettings = networkSettings
        setTunnelNetworkSettings(networkSettings) { [weak self] error in
            if let error {
                self?.logError("Failed to update proxy settings: \(error.localizedDescription)")
            }
        }
    }

    func writeDebugMessage(_ message: String?) {
        if let message { logInfo("libbox: \(message)") }
    }
}

extension PacketTunnelProvider: LibboxPlatformInterfaceProtocol {
    func autoDetectControl(_ fd: Int32) throws {}

    func clearDNSCache() {}

    func closeDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32, destinationAddress: String?, destinationPort: Int32) throws -> LibboxConnectionOwner {
        throw PacketTunnelError.connectionOwnerUnavailable
    }

    func getInterfaces() throws -> any LibboxNetworkInterfaceIteratorProtocol {
        guard let pathMonitor else {
            throw PacketTunnelError.defaultInterfaceMonitorUnavailable
        }

        let path = pathMonitor.currentPath
        guard path.status != .unsatisfied else {
            return NetworkInterfaceIterator([])
        }

        let interfaces = path.availableInterfaces.map { interface in
            let item = LibboxNetworkInterface()
            item.name = interface.name
            item.index = Int32(interface.index)
            switch interface.type {
            case .wifi:
                item.type = LibboxInterfaceTypeWIFI
            case .cellular:
                item.type = LibboxInterfaceTypeCellular
            case .wiredEthernet:
                item.type = LibboxInterfaceTypeEthernet
            default:
                item.type = LibboxInterfaceTypeOther
            }
            return item
        }
        return NetworkInterfaceIterator(interfaces)
    }

    func includeAllNetworks() -> Bool { true }

    func localDNSTransport() -> (any LibboxLocalDNSTransportProtocol)? { nil }

    func openTun(_ options: (any LibboxTunOptionsProtocol)?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        let settings = buildTunnelSettings(from: options)
        try setTunnelNetworkSettingsBlocking(settings)
        networkSettings = settings

        if let fd = self.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_?.pointee = fd
            logInfo("Opened packet tunnel fd from packetFlow socket")
            return
        }

        let fallbackFd = LibboxGetTunnelFileDescriptor()
        if fallbackFd != -1 {
            ret0_?.pointee = fallbackFd
            logInfo("Opened packet tunnel fd from Libbox fallback")
            return
        }

        logError("Missing packet tunnel file descriptor")
        throw PacketTunnelError.missingTunnelFileDescriptor
    }

    func readWIFIState() -> LibboxWIFIState? { nil }

    func send(_ notification: LibboxNotification?) throws {}

    func startDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        guard let listener else { return }

        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            self?.updateDefaultInterface(listener, path: path)
            monitor.pathUpdateHandler = { [weak self] path in
                self?.updateDefaultInterface(listener, path: path)
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        updateDefaultInterface(listener, path: monitor.currentPath)
    }

    func systemCertificates() -> (any LibboxStringIteratorProtocol)? { nil }

    func underNetworkExtension() -> Bool { true }

    func usePlatformAutoDetectControl() -> Bool { false }

    func useProcFS() -> Bool { false }

    private func updateDefaultInterface(_ listener: any LibboxInterfaceUpdateListenerProtocol, path: Network.NWPath) {
        guard path.status != .unsatisfied,
              let defaultInterface = path.availableInterfaces.first else {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        listener.updateDefaultInterface(
            defaultInterface.name,
            interfaceIndex: Int32(defaultInterface.index),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }

    private func buildTunnelSettings(from options: (any LibboxTunOptionsProtocol)?) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: options?.getMTU() ?? 1500)

        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(addresses: ["fdfe:dcba:9876::1"], networkPrefixLengths: [126])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        settings.dnsSettings = NEDNSSettings(servers: dnsServers(from: options))
        return settings
    }

    private func dnsServers(from options: (any LibboxTunOptionsProtocol)?) -> [String] {
        guard let value = try? options?.getDNSServerAddress().value else {
            return ["1.1.1.1", "8.8.8.8"]
        }

        let servers = value
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return servers.isEmpty ? ["1.1.1.1", "8.8.8.8"] : servers
    }

    private func setTunnelNetworkSettingsBlocking(_ settings: NEPacketTunnelNetworkSettings) throws {
        logInfo("Applying tunnel network settings")
        let semaphore = DispatchSemaphore(value: 0)
        var capturedError: Error?
        setTunnelNetworkSettings(settings) { error in
            capturedError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let capturedError {
            throw capturedError
        }
        logInfo("Tunnel network settings applied")
    }

    private func logInfo(_ message: String) {
        logger.info("\(message, privacy: .public)")
        appendSharedLog(level: "info", message: message)
    }

    private func logError(_ message: String) {
        logger.error("\(message, privacy: .public)")
        appendSharedLog(level: "error", message: message)
    }

    private func appendSharedLog(level: String, message: String) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }

        let line = "\(Self.timestamp()) [\(level)] \(message)\n"
        let fileURL = containerURL.appendingPathComponent(extensionLogFileName)
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

private final class NetworkInterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    private var iterator: IndexingIterator<[LibboxNetworkInterface]>
    private var nextValue: LibboxNetworkInterface?

    init(_ interfaces: [LibboxNetworkInterface]) {
        self.iterator = interfaces.makeIterator()
    }

    func hasNext() -> Bool {
        nextValue = iterator.next()
        return nextValue != nil
    }

    func next() -> LibboxNetworkInterface? {
        nextValue
    }
}
