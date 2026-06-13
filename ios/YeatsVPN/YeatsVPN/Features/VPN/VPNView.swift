import SwiftUI

struct VPNView: View {
    @Environment(\.openURL) private var openURL
    @StateObject var viewModel: VPNViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let action = viewModel.actionMessage {
                        ActionBanner(message: action)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    subscriptionCard
                    qrCard
                    serverListCard
                    actionsCard
                    importCard

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }
                }
                .padding(20)
                .animation(.snappy, value: viewModel.actionMessage)
            }
            .refreshable { await viewModel.refresh() }
            .background(DS.background)
            .navigationTitle("VPN")
            .task { await viewModel.refresh() }
        }
    }

    // MARK: - Subscription Card

    private var subscriptionCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack {
                    Label("Subscription", systemImage: "link")
                        .font(.headline)
                    Spacer()
                }
                Text(viewModel.subscriptionURL.isEmpty ? "No subscription yet" : viewModel.subscriptionURL)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
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
    }

    // MARK: - QR Card

    private var qrCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack {
                    Label("QR Code", systemImage: "qrcode")
                        .font(.headline)
                    Spacer()
                }
                if let image = viewModel.qrImage() {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    ContentUnavailableView("No Subscription", systemImage: "qrcode", description: Text("Connect or refresh to generate a QR code."))
                }
            }
        }
    }

    // MARK: - Server List Card

    private var serverListCard: some View {
        Group {
            if !viewModel.servers.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Available Servers", systemImage: "server.rack")
                                .font(.headline)
                            Spacer()
                            Text("\(viewModel.servers.count)")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DS.blue.opacity(0.15), in: Capsule())
                        }
                        ForEach(viewModel.servers) { server in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.displayName)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(server.address):\(server.port)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(server.proto.rawValue.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(DS.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(DS.blue.opacity(0.12), in: Capsule())
                            }
                            .padding(.vertical, 2)
                            if server.id != viewModel.servers.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    Label("Actions", systemImage: "wrench.and.screwdriver")
                        .font(.headline)
                    Spacer()
                }
                SecondaryButton(title: "Reset Traffic Counter", systemImage: "arrow.counterclockwise") {
                    Task { await viewModel.resetTraffic() }
                }
                SecondaryButton(title: "Regenerate Subscription", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await viewModel.regenerateSubscription() }
                }
            }
        }
    }

    // MARK: - Import Card

    private var importCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    Label("Import to App", systemImage: "square.and.arrow.down")
                        .font(.headline)
                    Spacer()
                }
                SecondaryButton(title: "Import into Happ", systemImage: "arrow.down.app.fill") {
                    if let url = viewModel.importURL(scheme: "happ") { openURL(url) }
                }
                SecondaryButton(title: "Import into Streisand", systemImage: "paperplane.fill") {
                    if let url = viewModel.importURL(scheme: "streisand") { openURL(url) }
                }
            }
        }
    }
}

struct ActionBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    VPNView(viewModel: VPNViewModel(environment: .preview()))
        .environmentObject(AppEnvironment.preview())
}
