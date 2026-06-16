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
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.environment.debugLog.importExtensionLogs()
            }
            .store(in: &cancellables)

        environment.debugLog.importExtensionLogs()
    }

    var progress: Double {
        guard let profile, profile.trafficLimitGb > 0 else { return 0 }
        return min(profile.trafficUsedGb / profile.trafficLimitGb, 1)
    }

    func refresh() async {
        guard !isLoading else { return }
        environment.debugLog.importExtensionLogs()
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let profileResult = environment.vpnService.profile()
            async let usageResult = environment.vpnService.usage()
            let freshProfile = try await profileResult
            let freshUsage = try await usageResult
            self.usage = freshUsage
            self.profile = freshProfile.applying(usage: freshUsage)
            environment.vpnProfile = self.profile
            if connectionState.isActive, let url = self.profile?.subscriptionUrl, !url.isEmpty {
                try? await environment.networkExtension.refreshConfiguration(subscriptionURL: url)
            }
        } catch is CancellationError {
            return
        } catch APIError.transport(let message) where message.lowercased() == "cancelled" {
            return
        } catch {
            errorMessage = error.localizedDescription
            environment.debugLog.error("Home refresh failed: \(error.localizedDescription)")
        }
    }

    func connectTapped() async {
        environment.debugLog.importExtensionLogs()
        guard let url = profile?.subscriptionUrl else { return }

        // Re-check actual NE status to avoid acting on stale UI state
        let freshState = await environment.networkExtension.currentState()
        if freshState != connectionState {
            environment.connectionState = freshState
        }

        switch freshState {
        case .connected, .connecting:
            environment.connectionState = .disconnecting
            await environment.networkExtension.disconnect()
            let state = await environment.networkExtension.currentState()
            environment.connectionState = state
        case .disconnected, .disconnecting, .unavailable:
            environment.connectionState = .connecting
            do {
                environment.debugLog.clear()
                environment.debugLog.info("Starting fresh VPN connection attempt")
                try await environment.networkExtension.connect(subscriptionURL: url)
                try? await Task.sleep(for: .seconds(1))
                let state = await environment.networkExtension.currentState()
                environment.connectionState = state
                environment.debugLog.importExtensionLogs()
                if state == .connected {
                    // Drop DNS/connection state cached while the tunnel was
                    // coming up (empty resolutions cause -1009 on api.yeats.uz)
                    environment.refreshNetworkSession?()
                    // Notify backend after tunnel is confirmed up — request goes
                    // through TUN → direct outbound, avoiding NECP block on en0
                    Task { _ = try? await environment.vpnService.enable() }
                    await refresh()
                }
            } catch {
                environment.connectionState = .unavailable(error.localizedDescription)
                environment.debugLog.error("Connect failed: \(error.localizedDescription)")
                environment.debugLog.importExtensionLogs()
            }
        }
    }

    func clearLogs() {
        environment.debugLog.clear()
    }
}
