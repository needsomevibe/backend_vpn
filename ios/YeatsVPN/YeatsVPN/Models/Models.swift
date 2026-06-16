import Foundation

struct AuthResponse: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let user: UserProfile
}

struct RefreshResponse: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let user: UserProfile
}

struct UserProfile: Codable, Equatable, Identifiable {
    let id: String
    let email: String
    let status: String
    let createdAt: Date?
    let vpn: VPNAccount?
    let vpnAccount: VPNAccount?
    let subscription: Subscription?
    let devices: [Device]?

    var effectiveVPN: VPNAccount? { vpn ?? vpnAccount }
}

struct VPNAccount: Codable, Equatable, Identifiable {
    let id: String
    let remnawaveUuid: String
    let remnawaveShortUuid: String?
    let username: String
    let status: String
    let trafficLimitBytes: String
    let usedTrafficBytes: String
    let expiresAt: Date?
    let subscriptionUrl: String
}

struct VPNProfile: Codable, Equatable {
    let status: String
    let subscriptionUrl: String
    let trafficUsedGb: Double
    let trafficLimitGb: Double
    let expiresAt: Date?
    let nodeLocation: String?

    init(status: String, subscriptionUrl: String, trafficUsedGb: Double, trafficLimitGb: Double, expiresAt: Date?, nodeLocation: String?) {
        self.status = status
        self.subscriptionUrl = subscriptionUrl
        self.trafficUsedGb = trafficUsedGb
        self.trafficLimitGb = trafficLimitGb
        self.expiresAt = expiresAt
        self.nodeLocation = nodeLocation
    }

    init(account: VPNAccount) {
        let used = Double(account.usedTrafficBytes) ?? 0
        let limit = Double(account.trafficLimitBytes) ?? 0
        self.status = account.status.lowercased()
        self.subscriptionUrl = account.subscriptionUrl
        self.trafficUsedGb = used / 1_073_741_824
        self.trafficLimitGb = limit / 1_073_741_824
        self.expiresAt = account.expiresAt
        self.nodeLocation = nil
    }

    func applying(usage: VPNUsage) -> VPNProfile {
        VPNProfile(
            status: status,
            subscriptionUrl: subscriptionUrl,
            trafficUsedGb: usage.usedTrafficGb,
            trafficLimitGb: usage.trafficLimitGb,
            expiresAt: expiresAt,
            nodeLocation: usage.nodeLocation ?? nodeLocation
        )
    }
}

struct VPNUsage: Codable, Equatable {
    let usedTrafficBytes: String
    let usedTrafficGb: Double
    let trafficLimitBytes: String
    let trafficLimitGb: Double
    let nodeLocation: String?
}

struct Subscription: Codable, Equatable, Identifiable {
    let id: String
    let status: String
    let expiresAt: Date?
    let provider: String
    let plan: Plan?
}

struct Plan: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let trafficLimitGb: Int
    let deviceLimit: Int
    let durationDays: Int
    let priceCents: Int
    let currency: String
}

struct Device: Codable, Equatable, Identifiable {
    let id: String
    let deviceId: String
    let platform: String
    let name: String?
    let lastSeenAt: Date?
}

struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let deviceId: String
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
    let deviceId: String?
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

struct AppleLoginRequest: Encodable {
    let identityToken: String
    let authorizationCode: String?
    let deviceId: String
    let fullName: String?
}

// MARK: - VPN Action Responses

struct VPNToggleResponse: Codable, Equatable {
    let id: String?
    let status: String?
    let success: Bool?
}

struct VPNResetTrafficResponse: Codable, Equatable {
    let success: Bool
}

struct VPNRegenerateResponse: Codable, Equatable {
    let subscriptionUrl: String
}

// MARK: - Server Configuration (parsed from subscription URL)

struct ServerConfig: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let port: Int
    let proto: ProxyProtocol
    let rawURI: String
    let countryCode: String?

    var displayName: String {
        if let code = countryCode {
            return "\(flagEmoji(code)) \(name)"
        }
        return name
    }
}

enum ProxyProtocol: String, Codable, CaseIterable {
    case vless = "vless"
    case vmess = "vmess"
    case trojan = "trojan"
    case shadowsocks = "ss"
    case hysteria2 = "hy2"
    case unknown = "unknown"
}

// MARK: - App Settings

struct AppSettings: Codable, Equatable {
    var autoConnect: Bool
    var killSwitch: Bool
    var selectedDNS: DNSOption
    var selectedServerId: String?

    static let `default` = AppSettings(
        autoConnect: false,
        killSwitch: false,
        selectedDNS: .cloudflare,
        selectedServerId: nil
    )
}

enum DNSOption: String, Codable, CaseIterable, Identifiable {
    case cloudflare = "1.1.1.1"
    case google = "8.8.8.8"
    case quad9 = "9.9.9.9"
    case adguard = "94.140.14.14"
    case system = "System"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cloudflare: return "Cloudflare (1.1.1.1)"
        case .google: return "Google (8.8.8.8)"
        case .quad9: return "Quad9 (9.9.9.9)"
        case .adguard: return "AdGuard (94.140.14.14)"
        case .system: return "System Default"
        }
    }

    var servers: [String] {
        switch self {
        case .cloudflare: return ["1.1.1.1", "1.0.0.1"]
        case .google: return ["8.8.8.8", "8.8.4.4"]
        case .quad9: return ["9.9.9.9", "149.112.112.112"]
        case .adguard: return ["94.140.14.14", "94.140.15.15"]
        case .system: return []
        }
    }
}

// MARK: - Helpers

private func flagEmoji(_ countryCode: String) -> String {
    let base: UInt32 = 127397
    return countryCode.uppercased().unicodeScalars.compactMap {
        UnicodeScalar(base + $0.value).map(String.init)
    }.joined()
}
