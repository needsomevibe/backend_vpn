import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

@MainActor
final class VPNViewModel: ObservableObject {
    @Published var profile: VPNProfile?
    @Published var servers: [ServerConfig] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var actionMessage: String?

    private let environment: AppEnvironment
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment) {
        self.environment = environment
        self.profile = environment.vpnProfile
        self.servers = environment.servers

        environment.$servers
            .receive(on: RunLoop.main)
            .sink { [weak self] servers in self?.servers = servers }
            .store(in: &cancellables)
    }

    var subscriptionURL: String {
        profile?.subscriptionUrl ?? ""
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            profile = try await environment.vpnService.profile()
            environment.vpnProfile = profile
            if let url = profile?.subscriptionUrl, !url.isEmpty {
                try? await environment.networkExtension.refreshConfiguration(subscriptionURL: url)
            }
            await environment.loadServers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copySubscriptionURL() {
        UIPasteboard.general.string = subscriptionURL
        showAction("Copied to clipboard")
    }

    func resetTraffic() async {
        do {
            _ = try await environment.vpnService.resetTraffic()
            showAction("Traffic reset")
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func regenerateSubscription() async {
        do {
            let result = try await environment.vpnService.regenerateSubscription()
            showAction("New subscription URL generated")
            // Update the profile with the new URL
            if let currentProfile = profile {
                profile = VPNProfile(
                    status: currentProfile.status,
                    subscriptionUrl: result.subscriptionUrl,
                    trafficUsedGb: currentProfile.trafficUsedGb,
                    trafficLimitGb: currentProfile.trafficLimitGb,
                    expiresAt: currentProfile.expiresAt,
                    nodeLocation: currentProfile.nodeLocation
                )
                environment.vpnProfile = profile
                try? await environment.networkExtension.refreshConfiguration(subscriptionURL: result.subscriptionUrl)
            }
            await environment.loadServers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func qrImage() -> UIImage? {
        guard let data = subscriptionURL.data(using: .utf8), !data.isEmpty else { return nil }
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = context.createCGImage(output, from: output.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    func importURL(scheme: String) -> URL? {
        guard let encoded = subscriptionURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "\(scheme)://import?url=\(encoded)")
    }

    private func showAction(_ message: String) {
        actionMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            self.actionMessage = nil
        }
    }
}
