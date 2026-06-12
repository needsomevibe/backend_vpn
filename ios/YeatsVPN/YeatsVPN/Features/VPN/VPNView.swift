import SwiftUI

struct VPNView: View {
    @Environment(\.openURL) private var openURL
    @StateObject var viewModel: VPNViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    GlassCard {
                        VStack(spacing: 16) {
                            Text("Subscription")
                                .font(.title2.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(viewModel.subscriptionURL.isEmpty ? "No subscription yet" : viewModel.subscriptionURL)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack {
                                SecondaryButton(title: "Copy", systemImage: "doc.on.doc.fill") {
                                    viewModel.copySubscriptionURL()
                                }
                                if !viewModel.subscriptionURL.isEmpty {
                                    ShareLink(item: viewModel.subscriptionURL) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 48)
                                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(spacing: 16) {
                            Text("QR Code")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let image = viewModel.qrImage() {
                                Image(uiImage: image)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 240)
                                    .padding(18)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            } else {
                                ContentUnavailableView("No Subscription", systemImage: "qrcode", description: Text("Create or refresh your VPN profile."))
                            }
                        }
                    }

                    GlassCard {
                        VStack(spacing: 12) {
                            SecondaryButton(title: "Import into Happ", systemImage: "arrow.down.app.fill") {
                                if let url = viewModel.importURL(scheme: "happ") { openURL(url) }
                            }
                            SecondaryButton(title: "Import into Streisand", systemImage: "paperplane.fill") {
                                if let url = viewModel.importURL(scheme: "streisand") { openURL(url) }
                            }
                        }
                    }

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }
                }
                .padding(20)
            }
            .refreshable { await viewModel.refresh() }
            .background(DS.background)
            .navigationTitle("VPN")
            .task { await viewModel.refresh() }
        }
    }
}

#Preview {
    VPNView(viewModel: VPNViewModel(environment: .preview()))
        .environmentObject(AppEnvironment.preview())
}
