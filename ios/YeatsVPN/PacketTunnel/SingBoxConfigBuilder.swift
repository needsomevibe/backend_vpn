import Foundation

// MARK: - Sing-Box Configuration Builder

/// Generates a sing-box JSON configuration from raw subscription content
/// (base64-decoded proxy URI lines: vless://, vmess://, trojan://, ss://, hy2://).
enum SingBoxConfigBuilder {
    struct BuildResult {
        let config: String
        let outboundCount: Int
        let selectedTag: String
        let selectedServer: String
    }

    static func build(from rawSubscription: String, selectedIndex: Int = 0) throws -> BuildResult {
        let subscription = normalizedSubscription(rawSubscription)
        let lines = subscription
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var outbounds: [[String: Any]] = []
        for (i, line) in lines.enumerated() {
            if let ob = parseOutbound(from: line, tag: "proxy-\(i)") {
                outbounds.append(ob)
            }
        }

        guard !outbounds.isEmpty else { throw SingBoxConfigError.unsupportedSubscription }

        let mainTag = (selectedIndex < outbounds.count
            ? outbounds[selectedIndex]["tag"]
            : outbounds[0]["tag"]) as? String ?? "proxy-0"

        let tags = outbounds.compactMap { $0["tag"] as? String }

        let selector: [String: Any] = [
            "type": "selector",
            "tag": "proxy",
            "outbounds": tags,
            "default": mainTag,
        ]
        let direct: [String: Any] = ["type": "direct", "tag": "direct", "domain_strategy": "prefer_ipv4"]

        let serverDomains = outbounds
            .compactMap { $0["server"] as? String }
            .filter { !$0.isEmpty && !isIPAddress($0) }
            .uniqued()

        let config: [String: Any] = [
            "log": ["level": "info", "timestamp": true],
            "dns": buildDNS(serverDomains: serverDomains),
            "inbounds": [buildTunInbound()],
            "outbounds": [selector] + outbounds + [direct],
            "route": buildRoute(serverDomains: serverDomains),
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            throw SingBoxConfigError.invalidJSON
        }
        let selectedServer = (outbounds[selectedIndex < outbounds.count ? selectedIndex : 0]["server"] as? String) ?? "unknown"
        return BuildResult(
            config: json,
            outboundCount: outbounds.count,
            selectedTag: mainTag,
            selectedServer: selectedServer
        )
    }

    // MARK: - Top-Level Sections

    private static func buildDNS(serverDomains: [String]) -> [String: Any] {
        var rules: [[String: Any]] = []
        if !serverDomains.isEmpty {
            rules.append(["domain": serverDomains, "action": "route", "server": "dns-direct"])
        }
        rules.append(["action": "route", "server": "dns-remote"])

        return [
            "servers": [
                ["type": "https", "tag": "dns-remote", "server": "1.1.1.1", "detour": "proxy"],
                ["type": "udp", "tag": "dns-direct", "server": "1.1.1.1", "detour": "direct"],
            ],
            "rules": rules,
            "final": "dns-remote",
            "strategy": "prefer_ipv4",
        ]
    }

    private static func buildTunInbound() -> [String: Any] {
        [
            "type": "tun",
            "tag": "tun-in",
            "address": [
                "172.19.0.1/30",
            ],
            "mtu": 1500,
            "auto_route": true,
            "strict_route": false,
            "stack": "gvisor",
        ]
    }

    private static func buildRoute(serverDomains: [String]) -> [String: Any] {
        var rules: [[String: Any]] = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"],
        ]
        if !serverDomains.isEmpty {
            rules.append(["domain": serverDomains, "outbound": "direct"])
        }
        return [
            "rules": rules,
            "final": "proxy",
        ]
    }

    // MARK: - Outbound Dispatcher

    private static func parseOutbound(from uri: String, tag: String) -> [String: Any]? {
        if uri.hasPrefix("vless://")    { return parseVLESS(uri, tag: tag) }
        if uri.hasPrefix("vmess://")    { return parseVMess(uri, tag: tag) }
        if uri.hasPrefix("trojan://")   { return parseTrojan(uri, tag: tag) }
        if uri.hasPrefix("ss://")       { return parseShadowsocks(uri, tag: tag) }
        if uri.hasPrefix("hy2://") || uri.hasPrefix("hysteria2://") { return parseHysteria2(uri, tag: tag) }
        return nil
    }

    private static func normalizedSubscription(_ rawSubscription: String) -> String {
        let trimmed = rawSubscription.trimmingCharacters(in: .whitespacesAndNewlines)
        if containsSupportedURI(trimmed) {
            return trimmed
        }
        return base64Decode(trimmed) ?? trimmed
    }

    private static func containsSupportedURI(_ value: String) -> Bool {
        value.contains("vless://")
            || value.contains("vmess://")
            || value.contains("trojan://")
            || value.contains("ss://")
            || value.contains("hy2://")
            || value.contains("hysteria2://")
    }

    // MARK: - VLESS

    private static func parseVLESS(_ uri: String, tag: String) -> [String: Any]? {
        guard let url = URL(string: uri), let host = url.host, let uuid = url.user else { return nil }
        let port = url.port ?? 443
        let params = queryParams(url)

        var ob: [String: Any] = [
            "type": "vless", "tag": tag,
            "server": host, "server_port": port,
            "uuid": uuid,
        ]

        if let flow = params["flow"], !flow.isEmpty { ob["flow"] = flow }

        if let tls = buildTLS(params: params, host: host) { ob["tls"] = tls }
        if let transport = buildTransport(params: params) { ob["transport"] = transport }

        return ob
    }

    // MARK: - VMess

    private static func parseVMess(_ uri: String, tag: String) -> [String: Any]? {
        let raw = String(uri.dropFirst("vmess://".count))

        // VMess can be either JSON-encoded (v2ray standard) or URI-style
        if let jsonData = Data(base64Encoded: raw),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            return parseVMessJSON(json, tag: tag)
        }

        // URI-style: vmess://uuid@host:port?params#name
        guard let url = URL(string: uri), let host = url.host, let uuid = url.user else { return nil }
        let port = url.port ?? 443
        let params = queryParams(url)

        var ob: [String: Any] = [
            "type": "vmess", "tag": tag,
            "server": host, "server_port": port,
            "uuid": uuid,
            "security": params["encryption"] ?? "auto",
            "alter_id": 0,
        ]

        if let tls = buildTLS(params: params, host: host) { ob["tls"] = tls }
        if let transport = buildTransport(params: params) { ob["transport"] = transport }

        return ob
    }

    private static func parseVMessJSON(_ json: [String: Any], tag: String) -> [String: Any]? {
        guard let host = json["add"] as? String,
              let uuid = json["id"] as? String else { return nil }

        let port = (json["port"] as? Int)
            ?? Int(json["port"] as? String ?? "")
            ?? 443

        var ob: [String: Any] = [
            "type": "vmess", "tag": tag,
            "server": host, "server_port": port,
            "uuid": uuid,
            "security": json["scy"] as? String ?? "auto",
            "alter_id": (json["aid"] as? Int) ?? Int(json["aid"] as? String ?? "") ?? 0,
        ]

        let tls = json["tls"] as? String ?? ""
        if tls == "tls" {
            let sni = json["sni"] as? String ?? json["host"] as? String ?? host
            ob["tls"] = [
                "enabled": true,
                "server_name": sni,
            ] as [String: Any]
        }

        let net = json["net"] as? String ?? "tcp"
        if net != "tcp" {
            var transport: [String: Any] = ["type": net == "h2" ? "http" : net]
            let path = json["path"] as? String ?? ""
            let headerHost = json["host"] as? String ?? ""
            if net == "ws" {
                if !path.isEmpty { transport["path"] = path }
                if !headerHost.isEmpty { transport["headers"] = ["Host": headerHost] }
            } else if net == "grpc" {
                let serviceName = json["path"] as? String ?? ""
                if !serviceName.isEmpty { transport["service_name"] = serviceName }
            } else if net == "h2" || net == "http" {
                transport["type"] = "http"
                if !path.isEmpty { transport["path"] = path }
                if !headerHost.isEmpty { transport["host"] = [headerHost] }
            }
            ob["transport"] = transport
        }

        return ob
    }

    // MARK: - Trojan

    private static func parseTrojan(_ uri: String, tag: String) -> [String: Any]? {
        guard let url = URL(string: uri), let host = url.host else { return nil }
        let password = url.user ?? ""
        let port = url.port ?? 443
        let params = queryParams(url)

        var ob: [String: Any] = [
            "type": "trojan", "tag": tag,
            "server": host, "server_port": port,
            "password": password,
        ]

        let security = params["security"] ?? "tls"
        var tls: [String: Any] = [
            "enabled": true,
            "server_name": params["sni"] ?? host,
        ]
        if let fp = params["fp"], !fp.isEmpty {
            tls["utls"] = ["enabled": true, "fingerprint": fp]
        }
        if let alpn = params["alpn"], !alpn.isEmpty {
            tls["alpn"] = alpn.components(separatedBy: ",")
        }
        if security == "reality" {
            var reality: [String: Any] = ["enabled": true]
            if let pbk = params["pbk"] { reality["public_key"] = pbk }
            if let sid = params["sid"] { reality["short_id"] = sid }
            tls["reality"] = reality
        }
        ob["tls"] = tls

        if let transport = buildTransport(params: params) { ob["transport"] = transport }

        return ob
    }

    // MARK: - Shadowsocks

    private static func parseShadowsocks(_ uri: String, tag: String) -> [String: Any]? {
        // ss://base64(method:password)@host:port#name
        // or ss://base64(method:password@host:port)#name
        let raw = String(uri.dropFirst("ss://".count))
        let (decoded, _) = splitFragment(raw)

        var method = "", password = "", host = "", port = 443

        if let atRange = decoded.range(of: "@") {
            let userInfo = String(decoded[decoded.startIndex..<atRange.lowerBound])
            let serverPart = String(decoded[atRange.upperBound...])
            let decodedUserInfo = base64Decode(userInfo) ?? userInfo
            let parts = decodedUserInfo.components(separatedBy: ":")
            method = parts.first ?? ""
            password = parts.dropFirst().joined(separator: ":")
            let serverParts = serverPart.components(separatedBy: ":")
            host = serverParts.first ?? ""
            port = Int(serverParts.last ?? "") ?? 443
        } else if let fullDecoded = base64Decode(decoded) {
            // Everything is base64-encoded
            if let atRange = fullDecoded.range(of: "@") {
                let userInfo = String(fullDecoded[fullDecoded.startIndex..<atRange.lowerBound])
                let serverPart = String(fullDecoded[atRange.upperBound...])
                let parts = userInfo.components(separatedBy: ":")
                method = parts.first ?? ""
                password = parts.dropFirst().joined(separator: ":")
                let serverParts = serverPart.components(separatedBy: ":")
                host = serverParts.first ?? ""
                port = Int(serverParts.last ?? "") ?? 443
            }
        }

        guard !host.isEmpty, !method.isEmpty else { return nil }

        return [
            "type": "shadowsocks", "tag": tag,
            "server": host, "server_port": port,
            "method": method,
            "password": password,
        ]
    }

    // MARK: - Hysteria2

    private static func parseHysteria2(_ uri: String, tag: String) -> [String: Any]? {
        let cleaned = uri
            .replacingOccurrences(of: "hysteria2://", with: "hy2://")
        guard let url = URL(string: cleaned), let host = url.host else { return nil }
        let password = url.user ?? ""
        let port = url.port ?? 443
        let params = queryParams(url)

        var ob: [String: Any] = [
            "type": "hysteria2", "tag": tag,
            "server": host, "server_port": port,
            "password": password,
        ]

        var tls: [String: Any] = [
            "enabled": true,
            "server_name": params["sni"] ?? host,
        ]
        if let alpn = params["alpn"], !alpn.isEmpty {
            tls["alpn"] = alpn.components(separatedBy: ",")
        }
        if let insecure = params["insecure"], insecure == "1" {
            tls["insecure"] = true
        }
        ob["tls"] = tls

        if let obfsType = params["obfs"], !obfsType.isEmpty {
            var obfs: [String: Any] = ["type": obfsType]
            if let obfsPassword = params["obfs-password"] {
                obfs["password"] = obfsPassword
            }
            ob["obfs"] = obfs
        }

        return ob
    }

    // MARK: - Shared Helpers

    private static func buildTLS(params: [String: String], host: String) -> [String: Any]? {
        let security = params["security"] ?? ""
        guard security == "tls" || security == "reality" else { return nil }

        var tls: [String: Any] = [
            "enabled": true,
            "server_name": params["sni"] ?? host,
        ]

        if let fp = params["fp"], !fp.isEmpty {
            tls["utls"] = ["enabled": true, "fingerprint": fp]
        }
        if let alpn = params["alpn"], !alpn.isEmpty {
            tls["alpn"] = alpn.components(separatedBy: ",")
        }

        if security == "reality" {
            var reality: [String: Any] = ["enabled": true]
            if let pbk = params["pbk"] { reality["public_key"] = pbk }
            if let sid = params["sid"] { reality["short_id"] = sid }
            tls["reality"] = reality
        }

        return tls
    }

    private static func buildTransport(params: [String: String]) -> [String: Any]? {
        let type = params["type"] ?? "tcp"
        guard type != "tcp" else { return nil }

        var transport: [String: Any] = [:]

        switch type {
        case "ws":
            transport["type"] = "ws"
            if let path = params["path"], !path.isEmpty {
                transport["path"] = path
            }
            if let headerHost = params["host"], !headerHost.isEmpty {
                transport["headers"] = ["Host": headerHost]
            }

        case "grpc":
            transport["type"] = "grpc"
            let serviceName = params["serviceName"] ?? params["service_name"] ?? params["serviceName".lowercased()]
            if let serviceName, !serviceName.isEmpty {
                transport["service_name"] = serviceName
            }

        case "http", "h2":
            transport["type"] = "http"
            if let path = params["path"], !path.isEmpty {
                transport["path"] = path
            }
            if let headerHost = params["host"], !headerHost.isEmpty {
                transport["host"] = [headerHost]
            }

        default:
            transport["type"] = type
        }

        return transport
    }

    private static func queryParams(_ url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return [:] }
        var dict: [String: String] = [:]
        for item in items {
            dict[item.name] = item.value ?? ""
        }
        return dict
    }

    private static func splitFragment(_ raw: String) -> (String, String?) {
        if let hashRange = raw.range(of: "#", options: .backwards) {
            let main = String(raw[raw.startIndex..<hashRange.lowerBound])
            let frag = String(raw[hashRange.upperBound...])
            return (main, frag)
        }
        return (raw, nil)
    }

    private static func base64Decode(_ string: String) -> String? {
        var padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        guard let data = Data(base64Encoded: padded) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func isIPAddress(_ string: String) -> Bool {
        var sin = sockaddr_in()
        var sin6 = sockaddr_in6()
        return string.withCString { cString in
            inet_pton(AF_INET, cString, &sin.sin_addr) == 1
                || inet_pton(AF_INET6, cString, &sin6.sin6_addr) == 1
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

enum SingBoxConfigError: LocalizedError {
    case unsupportedSubscription
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .unsupportedSubscription:
            return "Subscription does not contain a supported proxy URI."
        case .invalidJSON:
            return "Failed to generate sing-box JSON config."
        }
    }
}
