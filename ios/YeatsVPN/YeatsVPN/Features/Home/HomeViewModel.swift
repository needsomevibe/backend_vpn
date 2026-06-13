import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var profile: VPNProfile?
    @Published var usage: VPNUsage?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var connectionState: VPNConnectionState = .disconnected
    @Published var connectedSince: Date?
    @Published var logs: [DebugLogEntry] = []

    private let environment: AppEnvironment
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment) {
        self.environment = environment
        self.profile = environment.vpnProfile
        self.logs = environment.debugLog.entries
        self.connectionState = environment.connectionState
        self.connectedSince = environment.connectedSince

        environment.$connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.connectionState = state }
            .store(in: &cancellables)
        environment.$connectedSince
            .receive(on: RunLoop.main)
            .sink { [weak self] date in self?.connectedSince = date }
            .store(in: &cancellables)
        environment.debugLog.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] entries in self?.logs = entries }
            .store(in: &cancellables)
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
            async let profileResult = environment.vpnService.profile()
            async let usageResult = environment.vpnService.usage()
            self.profile = try await profileResult
            self.usage = try await usageResult
            environment.vpnProfile = self.profile
        } catch {
            errorMessage = error.localizedDescription
            environment.debugLog.error("Home refresh failed: \(error.localizedDescription)")
        }
    }

    func connectTapped() async {
        guard let url = profile?.subscriptionUrl else { return }
        switch connectionState {
        case .connected, .connecting:
            environment.connectionState = .disconnecting
            await environment.networkExtension.disconnect()
            let state = await environment.networkExtension.currentState()
            environment.connectionState = state
        case .disconnected, .disconnecting, .unavailable:
            environment.connectionState = .connecting
            do {
                // Enable VPN on the backend first
                _ = try? await environment.vpnService.enable()
                try await environment.networkExtension.connect(subscriptionURL: url)
                let state = await environment.networkExtension.currentState()
                environment.connectionState = state
            } catch {
                environment.connectionState = .unavailable(error.localizedDescription)
                environment.debugLog.error("Connect failed: \(error.localizedDescription)")
            }
        }
    }

    func clearLogs() {
        environment.debugLog.clear()
    }
}
