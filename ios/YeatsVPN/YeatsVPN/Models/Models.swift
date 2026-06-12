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
