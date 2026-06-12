import Foundation

protocol VPNServicing: Sendable {
    func profile() async throws -> VPNProfile
    func usage() async throws -> VPNUsage
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
}
