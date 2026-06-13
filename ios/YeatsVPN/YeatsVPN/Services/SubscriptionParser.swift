import Foundation

enum SubscriptionParser {

    static func fetchAndParse(subscriptionURL: String) async throws -> [ServerConfig] {
        guard let url = URL(string: subscriptionURL) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let raw = String(data: data, encoding: .utf8) else { return [] }
        return parse(raw)
    }

    static func parse(_ raw: String) -> [ServerConfig] {
        let decoded: String
        if let data = Data(base64Encoded: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           let str = String(data: data, encoding: .utf8) {
            decoded = str
        } else {
            decoded = raw
        }
        return decoded
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return parseLine(trimmed)
            }
    }

    private static func parseLine(_ line: String) -> ServerConfig? {
        if line.hasPrefix("vless://") { return parseVLESS(line) }
        if line.hasPrefix("vmess://") { return parseVMess(line) }
        if line.hasPrefix("trojan://") { return parseTrojan(line) }
        if line.hasPrefix("ss://") { return parseShadowsocks(line) }
        if line.hasPrefix("hy2://") || line.hasPrefix("hysteria2://") { return parseHysteria2(line) }
        return nil
    }

    // MARK: - VLESS

    private static func parseVLESS(_ uri: String) -> ServerConfig? {
        // vless://uuid@host:port?params#name
        guard let url = URL(string: uri),
              let host = url.host,
              let port = url.port else { return nil }
        let name = url.fragment?.removingPercentEncoding ?? host
        return ServerConfig(
            id: uri,
            name: name,
            address: host,
            port: port,
            proto: .vless,
            rawURI: uri,
            countryCode: guessCountry(name: name, address: host)
        )
    }

    // MARK: - VMess

    private static func parseVMess(_ uri: String) -> ServerConfig? {
        let payload = String(uri.dropFirst("vmess://".count))
        // try base64 JSON first
        if let data = Data(base64Encoded: payload),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let add = json["add"] as? String {
            let port = (json["port"] as? Int) ?? Int(json["port"] as? String ?? "") ?? 443
            let name = (json["ps"] as? String) ?? add
            return ServerConfig(
                id: uri,
                name: name,
                address: add,
                port: port,
                proto: .vmess,
                rawURI: uri,
                countryCode: guessCountry(name: name, address: add)
            )
        }
        // standard URI form vmess://uuid@host:port?params#name
        guard let url = URL(string: uri),
              let host = url.host,
              let port = url.port else { return nil }
        let name = url.fragment?.removingPercentEncoding ?? host
        return ServerConfig(
            id: uri,
            name: name,
            address: host,
            port: port,
            proto: .vmess,
            rawURI: uri,
            countryCode: guessCountry(name: name, address: host)
        )
    }

    // MARK: - Trojan

    private static func parseTrojan(_ uri: String) -> ServerConfig? {
        guard let url = URL(string: uri),
              let host = url.host,
              let port = url.port else { return nil }
        let name = url.fragment?.removingPercentEncoding ?? host
        return ServerConfig(
            id: uri,
            name: name,
            address: host,
            port: port,
            proto: .trojan,
            rawURI: uri,
            countryCode: guessCountry(name: name, address: host)
        )
    }

    // MARK: - Shadowsocks

    private static func parseShadowsocks(_ uri: String) -> ServerConfig? {
        // ss://base64(method:password)@host:port#name
        // or ss://base64(method:password@host:port)#name
        let stripped = String(uri.dropFirst("ss://".count))
        let parts = stripped.split(separator: "#", maxSplits: 1)
        let name = parts.count > 1 ? String(parts[1]).removingPercentEncoding ?? String(parts[1]) : nil
        let main = String(parts[0])

        if main.contains("@") {
            let atParts = main.split(separator: "@", maxSplits: 1)
            let hostPort = String(atParts.last ?? "")
            let (host, port) = parseHostPort(hostPort)
            guard let host else { return nil }
            return ServerConfig(
                id: uri,
                name: name ?? host,
                address: host,
                port: port ?? 443,
                proto: .shadowsocks,
                rawURI: uri,
                countryCode: guessCountry(name: name ?? host, address: host)
            )
        }

        // try full base64 decode
        if let data = Data(base64Encoded: main),
           let decoded = String(data: data, encoding: .utf8) {
            let atParts = decoded.split(separator: "@", maxSplits: 1)
            if atParts.count == 2 {
                let (host, port) = parseHostPort(String(atParts[1]))
                guard let host else { return nil }
                return ServerConfig(
                    id: uri,
                    name: name ?? host,
                    address: host,
                    port: port ?? 443,
                    proto: .shadowsocks,
                    rawURI: uri,
                    countryCode: guessCountry(name: name ?? host, address: host)
                )
            }
        }
        return nil
    }

    // MARK: - Hysteria2

    private static func parseHysteria2(_ uri: String) -> ServerConfig? {
        guard let url = URL(string: uri),
              let host = url.host else { return nil }
        let port = url.port ?? 443
        let name = url.fragment?.removingPercentEncoding ?? host
        return ServerConfig(
            id: uri,
            name: name,
            address: host,
            port: port,
            proto: .hysteria2,
            rawURI: uri,
            countryCode: guessCountry(name: name, address: host)
        )
    }

    // MARK: - Helpers

    private static func parseHostPort(_ string: String) -> (String?, Int?) {
        if let last = string.lastIndex(of: ":") {
            let host = String(string[string.startIndex..<last])
            let port = Int(string[string.index(after: last)...])
            return (host.isEmpty ? nil : host, port)
        }
        return (string.isEmpty ? nil : string, nil)
    }

    private static let countryMap: [(pattern: String, code: String)] = [
        ("US", "US"), ("United States", "US"), ("America", "US"), ("USA", "US"),
        ("DE", "DE"), ("Germany", "DE"), ("Frankfurt", "DE"),
        ("NL", "NL"), ("Netherlands", "NL"), ("Amsterdam", "NL"),
        ("GB", "GB"), ("UK", "GB"), ("United Kingdom", "GB"), ("London", "GB"),
        ("FR", "FR"), ("France", "FR"), ("Paris", "FR"),
        ("JP", "JP"), ("Japan", "JP"), ("Tokyo", "JP"),
        ("SG", "SG"), ("Singapore", "SG"),
        ("KR", "KR"), ("Korea", "KR"), ("Seoul", "KR"),
        ("CA", "CA"), ("Canada", "CA"), ("Toronto", "CA"),
        ("AU", "AU"), ("Australia", "AU"), ("Sydney", "AU"),
        ("FI", "FI"), ("Finland", "FI"), ("Helsinki", "FI"),
        ("SE", "SE"), ("Sweden", "SE"),
        ("TR", "TR"), ("Turkey", "TR"), ("Istanbul", "TR"),
        ("RU", "RU"), ("Russia", "RU"), ("Moscow", "RU"),
        ("UZ", "UZ"), ("Uzbekistan", "UZ"), ("Tashkent", "UZ"),
    ]

    private static func guessCountry(name: String, address: String) -> String? {
        let combined = "\(name) \(address)".uppercased()
        for entry in countryMap {
            if combined.contains(entry.pattern.uppercased()) {
                return entry.code
            }
        }
        return nil
    }
}
