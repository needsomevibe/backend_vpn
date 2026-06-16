import os.log
import Network
import NetworkExtension
import Libbox

final class PacketTunnelProvider: NEPacketTunnelProvider {
private let logger = Logger(subsystem: "uz.yeats.vpn.PacketTunnel", category: "PacketTunnel")
private let appGroupIdentifier = "group.uz.yeats.vpn"
private let extensionLogFileName = "vpn-extension.log"
private let cachedConfigFileName = "vpn-singbox-config.json"
private var subscriptionURL: String?
private var boxService: LibboxCommandServer?
private var networkSettings: NEPacketTunnelNetworkSettings?
private var pathMonitor: NWPathMonitor?
private var recentLogLines: [String] = []
private var startupPhase: StartupPhase = .idle
private var lastStartupError: String?

private enum StartupPhase: String, Encodable {
    case idle
    case downloadingSubscription
    case buildingConfig
    case validatingConfig
    case applyingSettings
    case startingLibbox
    case running
    case failed
}

override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
    setPhase(.idle)
    logInfo("PacketTunnel startTunnel entered")
    let providerURL = (protocolConfiguration as? NETunnelProviderProtocol)?
        .providerConfiguration?["subscriptionUrl"] as? String
    let optionURL = options?["subscriptionUrl"] as? String
    subscriptionURL = optionURL ?? providerURL
    logInfo("PacketTunnel subscription URL present: \(subscriptionURL != nil)")

    guard let subscriptionURL, let url = URL(string: subscriptionURL) else {
        logError("Missing subscription URL in provider configuration/options")
        completionHandler(PacketTunnelError.missingSubscriptionURL)
        return
    }

    Task {
        do {
            logInfo("PacketTunnel start requested")
            let config = try await resolveStartupConfig(url: url)

            setPhase(.startingLibbox)
            try setupLibbox()

            var commandError: NSError?
            let box = LibboxNewCommandServer(self as LibboxCommandServerHandlerProtocol, self as LibboxPlatformInterfaceProtocol, &commandError)
            if let commandError {
                throw commandError
            }
            guard let box else {
                throw PacketTunnelError.libboxUnavailable
            }
            logInfo("Starting Libbox command server")
            try box.start()

            logInfo("Starting Libbox service")
            try box.startOrReloadService(config, options: LibboxOverrideOptions())
            self.boxService = box

            setPhase(.running)
            logInfo("VPN started successfully with Sing-Box integration")
            completionHandler(nil)

            // Refresh cached config in the background so the next start is fast
            // and the cache stays current with the latest subscription.
            refreshConfigCacheInBackground(url: url)
        } catch {
            setPhase(.failed, error: error.localizedDescription)
            logError("Failed to start VPN: \(error.localizedDescription)")
            completionHandler(error)
        }
    }
}

// MARK: - Startup Config Resolution & Caching

/// Returns a validated sing-box config to start with. Uses a previously
/// cached config for the same subscription URL (fast path, no network) when
/// available and valid; otherwise downloads and builds it.
private func resolveStartupConfig(url: URL) async throws -> String {
    if let cached = readCachedConfig(for: url) {
        setPhase(.validatingConfig)
        var checkError: NSError?
        if LibboxCheckConfig(cached, &checkError) {
            logInfo("Using cached sing-box config, bytes: \(cached.utf8.count) — skipping subscription download")
            return cached
        }
        logInfo("Cached config invalid, discarding: \(checkError?.localizedDescription ?? "unknown")")
        clearCachedConfig()
    }

    setPhase(.downloadingSubscription)
    logInfo("Downloading subscription for tunnel startup")
    let config = try await downloadAndBuildConfig(url: url)

    setPhase(.validatingConfig)
    var checkError: NSError?
    if !LibboxCheckConfig(config, &checkError) {
        throw checkError ?? PacketTunnelError.invalidSingBoxConfig
    }
    logInfo("Libbox config validation succeeded")
    writeCachedConfig(config, for: url)
    return config
}

/// Downloads the subscription and builds a sing-box config. No phase/state
/// side effects so it is safe to call from a background refresh task.
private func downloadAndBuildConfig(url: URL) async throws -> String {
    let (data, response) = try await URLSession.shared.data(from: url)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        throw PacketTunnelError.subscriptionHTTPStatus(http.statusCode)
    }
    guard let rawSubscription = String(data: data, encoding: .utf8) else {
        throw PacketTunnelError.invalidSubscriptionData
    }
    let buildResult = try SingBoxConfigBuilder.build(from: rawSubscription)
    logInfo("Generated sing-box config, bytes: \(buildResult.config.utf8.count), outbounds: \(buildResult.outboundCount), selected: \(buildResult.selectedTag), server: \(buildResult.selectedServer)")
    return buildResult.config
}

/// After the tunnel is up, refresh the cached config from the latest
/// subscription so the next start is both fast and current. Does not reload
/// the running service, avoiding any mid-session interruption.
private func refreshConfigCacheInBackground(url: URL) {
    Task.detached(priority: .utility) { [weak self] in
        guard let self else { return }
        do {
            let fresh = try await self.downloadAndBuildConfig(url: url)
            var checkError: NSError?
            guard LibboxCheckConfig(fresh, &checkError) else {
                self.logInfo("Background config refresh produced invalid config, keeping existing cache")
                return
            }
            self.writeCachedConfig(fresh, for: url)
            self.logInfo("Refreshed cached sing-box config for next start")
        } catch {
            self.logInfo("Background config refresh failed: \(error.localizedDescription)")
        }
    }
}

private struct CachedConfigEnvelope: Codable {
    let url: String
    let config: String
}

private var cachedConfigFileURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
        .appendingPathComponent(cachedConfigFileName)
}

private func readCachedConfig(for url: URL) -> String? {
    guard let fileURL = cachedConfigFileURL,
          let data = try? Data(contentsOf: fileURL),
          let cached = try? JSONDecoder().decode(CachedConfigEnvelope.self, from: data),
          cached.url == url.absoluteString,
          !cached.config.isEmpty else {
        return nil
    }
    return cached.config
}

private func writeCachedConfig(_ config: String, for url: URL) {
    guard let fileURL = cachedConfigFileURL else { return }
    let envelope = CachedConfigEnvelope(url: url.absoluteString, config: config)
    guard let data = try? JSONEncoder().encode(envelope) else { return }
    try? data.write(to: fileURL, options: [.atomic])
}

private func clearCachedConfig() {
    guard let fileURL = cachedConfigFileURL else { return }
    try? FileManager.default.removeItem(at: fileURL)
}

override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    logInfo("Stopping tunnel, reason: \(reason.rawValue)")
    boxService?.close()
    boxService = nil
    pathMonitor?.cancel()
    pathMonitor = nil
    networkSettings = nil
    subscriptionURL = nil
    startupPhase = .idle
    lastStartupError = nil
    completionHandler()
}

override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
    guard let completionHandler else { return }

    let status = PacketTunnelStatus(
        isRunning: startupPhase == .running,
        startupPhase: startupPhase.rawValue,
        lastError: lastStartupError,
        subscriptionURL: subscriptionURL,
        logs: recentLogLines
    )

    if let data = try? JSONEncoder().encode(status) {
        completionHandler(data)
    } else {
        let fallback = #"{"isRunning":false,"startupPhase":"\#(startupPhase.rawValue)","logs":[]}"#
        completionHandler(Data(fallback.utf8))
    }
}

}

private struct PacketTunnelStatus: Encodable {
let isRunning: Bool
let startupPhase: String
let lastError: String?
let subscriptionURL: String?
let logs: [String]
}

private enum PacketTunnelError: LocalizedError {
case missingSubscriptionURL
case invalidSubscriptionData
case subscriptionHTTPStatus(Int)
case libboxUnavailable
case invalidSingBoxConfig
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
    case .invalidSingBoxConfig:
        return "Generated sing-box config is invalid."
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
            logInfo("Default interface monitor unavailable; returning empty interface list")
            return NetworkInterfaceIterator([])
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
        guard let ret0_ else {
            throw PacketTunnelError.missingTunnelFileDescriptor
        }

        ret0_.pointee = try runBlocking { [self] in
            try await openTunAsync(options)
        }
    }

    func readWIFIState() -> LibboxWIFIState? { nil }

    func send(_ notification: LibboxNotification?) throws {}

    func startDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        guard let listener else { return }

        logInfo("Starting default interface monitor")
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
            logInfo("Default interface unavailable")
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        logInfo("Default interface: \(defaultInterface.name), type: \(defaultInterface.type), expensive: \(path.isExpensive), constrained: \(path.isConstrained)")
        listener.updateDefaultInterface(
            defaultInterface.name,
            interfaceIndex: Int32(defaultInterface.index),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }

    private func openTunAsync(_ options: (any LibboxTunOptionsProtocol)?) async throws -> Int32 {
        logInfo("openTun requested by Libbox")
        let settings = buildTunnelSettings(from: options)
        try await setTunnelNetworkSettingsAsync(settings)
        networkSettings = settings

        let fd = LibboxGetTunnelFileDescriptor()
        if fd != -1 {
            logInfo("Opened packet tunnel fd from Libbox: \(fd)")
            return fd
        }

        logError("Missing packet tunnel file descriptor")
        throw PacketTunnelError.missingTunnelFileDescriptor
    }

    private func buildTunnelSettings(from options: (any LibboxTunOptionsProtocol)?) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        // Clamp MTU to 1280 — VLESS+TLS+IP overhead makes 1500 fragment packets
        let requestedMTU = Int(options?.getMTU() ?? 1280)
        settings.mtu = NSNumber(value: min(requestedMTU, 1280))

        let ipv4 = ipv4Settings(from: options)
        settings.ipv4Settings = ipv4

        if let ipv6 = ipv6Settings(from: options) {
            settings.ipv6Settings = ipv6
        }

        let dnsServers = dnsServers(from: options)
        let dnsSettings = NEDNSSettings(servers: dnsServers)
        dnsSettings.matchDomains = [""]
        dnsSettings.matchDomainsNoSearch = true
        settings.dnsSettings = dnsSettings
        logInfo("Built tunnel settings: mtu=\(settings.mtu ?? 0), dns=\(dnsServers.joined(separator: ","))")
        return settings
    }

    private func ipv4Settings(from options: (any LibboxTunOptionsProtocol)?) -> NEIPv4Settings {
        var addresses: [String] = []
        var masks: [String] = []
        if let iterator = options?.getInet4Address() {
            while iterator.hasNext() {
                guard let prefix = iterator.next() else { continue }
                addresses.append(prefix.address())
                masks.append(prefix.mask())
            }
        }

        if addresses.isEmpty || masks.isEmpty {
            addresses = ["172.19.0.1"]
            masks = ["255.255.255.252"]
        }

        let settings = NEIPv4Settings(addresses: addresses, subnetMasks: masks)
        let included = ipv4Routes(from: options?.getInet4RouteAddress())
        let excluded = ipv4Routes(from: options?.getInet4RouteExcludeAddress())
        settings.includedRoutes = included.isEmpty ? [NEIPv4Route.default()] : included
        settings.excludedRoutes = excluded
        logInfo("IPv4 tunnel addresses: \(addresses.joined(separator: ",")), routes: \(settings.includedRoutes?.count ?? 0), excluded: \(excluded.count)")
        return settings
    }

    private func ipv4Routes(from iterator: (any LibboxRoutePrefixIteratorProtocol)?) -> [NEIPv4Route] {
        guard let iterator else { return [] }
        var routes: [NEIPv4Route] = []
        while iterator.hasNext() {
            guard let prefix = iterator.next() else { continue }
            routes.append(NEIPv4Route(destinationAddress: prefix.address(), subnetMask: prefix.mask()))
        }
        return routes
    }

    private func ipv6Settings(from options: (any LibboxTunOptionsProtocol)?) -> NEIPv6Settings? {
        var addresses: [String] = []
        var prefixLengths: [NSNumber] = []
        if let iterator = options?.getInet6Address() {
            while iterator.hasNext() {
                guard let prefix = iterator.next() else { continue }
                addresses.append(prefix.address())
                prefixLengths.append(NSNumber(value: prefix.prefix()))
            }
        }

        guard !addresses.isEmpty, !prefixLengths.isEmpty else {
            return nil
        }

        let settings = NEIPv6Settings(addresses: addresses, networkPrefixLengths: prefixLengths)
        let included = ipv6Routes(from: options?.getInet6RouteAddress())
        let excluded = ipv6Routes(from: options?.getInet6RouteExcludeAddress())
        settings.includedRoutes = included.isEmpty ? [NEIPv6Route.default()] : included
        settings.excludedRoutes = excluded
        logInfo("IPv6 tunnel addresses: \(addresses.joined(separator: ",")), routes: \(settings.includedRoutes?.count ?? 0), excluded: \(excluded.count)")
        return settings
    }

    private func ipv6Routes(from iterator: (any LibboxRoutePrefixIteratorProtocol)?) -> [NEIPv6Route] {
        guard let iterator else { return [] }
        var routes: [NEIPv6Route] = []
        while iterator.hasNext() {
            guard let prefix = iterator.next() else { continue }
            routes.append(NEIPv6Route(destinationAddress: prefix.address(), networkPrefixLength: NSNumber(value: prefix.prefix())))
        }
        return routes
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

    private func setTunnelNetworkSettingsAsync(_ settings: NEPacketTunnelNetworkSettings) async throws {
        logInfo("Applying tunnel network settings")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: PacketTunnelError.libboxUnavailable)
                    return
                }

                self.setTunnelNetworkSettings(settings) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
        logInfo("Tunnel network settings applied")
    }

    private func setupLibbox() throws {
        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? FileManager.default.temporaryDirectory
        let baseURL = containerURL.appendingPathComponent("libbox", isDirectory: true)
        let workURL = baseURL.appendingPathComponent("work", isDirectory: true)
        let tempURL = baseURL.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)

        let options = LibboxSetupOptions()
        options.basePath = baseURL.path
        options.workingPath = workURL.path
        options.tempPath = tempURL.path
        options.logMaxLines = 1000
        options.debug = true

        var setupError: NSError?
        if !LibboxSetup(options, &setupError) {
            throw setupError ?? PacketTunnelError.libboxUnavailable
        }
        logInfo("Libbox setup completed at \(baseURL.path)")
    }

    private func setPhase(_ phase: StartupPhase, error: String? = nil) {
        startupPhase = phase
        if let error { lastStartupError = error }
        persistPhase()
    }

    private func persistPhase() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        let phaseFileURL = containerURL.appendingPathComponent("vpn-extension-phase.json")
        let value: [String: String?] = [
            "phase": startupPhase.rawValue,
            "error": lastStartupError,
            "timestamp": Self.timestamp()
        ]
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: phaseFileURL, options: [.atomic])
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
        recentLogLines.append(line.trimmingCharacters(in: .newlines))
        if recentLogLines.count > 80 {
            recentLogLines.removeFirst(recentLogLines.count - 80)
        }
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

private func runBlocking<T>(_ block: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = BlockingResultBox<T>()
    Task.detached(priority: .userInitiated) {
        do {
            box.result = .success(try await block())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.result.get()
}

private final class BlockingResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>!
}
