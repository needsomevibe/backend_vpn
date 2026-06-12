import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var profile: VPNProfile?
    @Published var usage: VPNUsage?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var connectionState: VPNConnectionState = .disconnected
    @Published var logs: [DebugLogEntry] = []

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        self.profile = environment.vpnProfile
        self.logs = environment.debugLog.entries
    }

    var progress: Double {
        guard let profile, profile.trafficLimitGb > 0 else { return 0 }
        return min(profile.trafficUsedGb / profile.trafficLimitGb, 1)
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let profile = environment.vpnService.profile()
            async let usage = environment.vpnService.usage()
            self.profile = try await profile
            self.usage = try await usage
            environment.vpnProfile = self.profile
            connectionState = await environment.networkExtension.currentState()
            logs = environment.debugLog.entries
        } catch {
            errorMessage = error.localizedDescription
            environment.debugLog.error("Home refresh failed: \(error.localizedDescription)")
            logs = environment.debugLog.entries
        }
    }

    func connectTapped() async {
        guard let url = profile?.subscriptionUrl else { return }
        switch connectionState {
        case .connected, .connecting:
            await environment.networkExtension.disconnect()
            connectionState = await environment.networkExtension.currentState()
            logs = environment.debugLog.entries
        case .disconnected, .unavailable:
            connectionState = .connecting
            do {
                try await environment.networkExtension.connect(subscriptionURL: url)
                connectionState = await environment.networkExtension.currentState()
                logs = environment.debugLog.entries
            } catch {
                connectionState = .unavailable(error.localizedDescription)
                environment.debugLog.error("Connect failed: \(error.localizedDescription)")
                logs = environment.debugLog.entries
            }
        }
    }

    func clearLogs() {
        environment.debugLog.clear()
        logs = []
    }
}
