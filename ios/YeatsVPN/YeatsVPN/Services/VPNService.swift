import Foundation

protocol VPNServicing: Sendable {
    func profile() async throws -> VPNProfile
    func usage() async throws -> VPNUsage
    func enable() async throws -> VPNToggleResponse
    func disable() async throws -> VPNToggleResponse
    func resetTraffic() async throws -> VPNResetTrafficResponse
    func regenerateSubscription() async throws -> VPNRegenerateResponse
    func plans() async throws -> [Plan]
}

final class VPNService: VPNServicing, @unchecked Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func profile() async throws -> VPNProfile {
        try await apiClient.request(.vpnProfile)
    }

    func usage() async throws -> VPNUsage {
        try await apiClient.request(.vpnUsage)
    }

    func enable() async throws -> VPNToggleResponse {
        try await apiClient.request(.vpnEnable)
    }

    func disable() async throws -> VPNToggleResponse {
        try await apiClient.request(.vpnDisable)
    }

    func resetTraffic() async throws -> VPNResetTrafficResponse {
        try await apiClient.request(.vpnResetTraffic)
    }

    func regenerateSubscription() async throws -> VPNRegenerateResponse {
        try await apiClient.request(.vpnRegenerateSubscription)
    }

    func plans() async throws -> [Plan] {
        try await apiClient.request(.plans)
    }
}
