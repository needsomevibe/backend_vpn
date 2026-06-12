import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

@MainActor
final class VPNViewModel: ObservableObject {
    @Published var profile: VPNProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let environment: AppEnvironment
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    init(environment: AppEnvironment) {
        self.environment = environment
        self.profile = environment.vpnProfile
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copySubscriptionURL() {
        UIPasteboard.general.string = subscriptionURL
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
}
