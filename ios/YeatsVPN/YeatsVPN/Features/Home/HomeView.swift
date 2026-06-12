import SwiftUI

struct HomeView: View {
    @StateObject var viewModel: HomeViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    connectionCard
                    usageCard
                    detailsCard
                    debugLogCard
                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }
                }
                .padding(20)
            }
            .refreshable { await viewModel.refresh() }
            .background(DS.background)
            .navigationTitle("Yeats VPN")
            .task { await viewModel.refresh() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Private tunnel")
                    .font(.largeTitle.bold())
                Text("Premium VPN access through Yeats.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            LogoMark(size: 54)
        }
    }

    private var connectionCard: some View {
        GlassCard {
            VStack(spacing: 20) {
                HStack {
                    StatusPill(text: viewModel.profile?.status ?? "Loading", isActive: viewModel.profile?.status == "active")
                    Spacer()
                    Label(viewModel.profile?.nodeLocation ?? "US", systemImage: "location.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await viewModel.connectTapped() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [DS.blue, DS.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 172, height: 172)
                            .shadow(color: DS.blue.opacity(0.28), radius: 30, y: 18)
                        Image(systemName: "power")
                            .font(.system(size: 58, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .opacity(viewModel.connectionState == .connecting ? 0.65 : 1)
                }
                .buttonStyle(.plain)
                Text(connectionText)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var usageCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Traffic")
                        .font(.headline)
                    Spacer()
                    Text("\((viewModel.profile?.trafficUsedGb ?? 0).gbDisplay) / \((viewModel.profile?.trafficLimitGb ?? 0).gbDisplay)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: viewModel.progress)
                    .tint(DS.blue)
                    .scaleEffect(y: 1.4)
            }
        }
    }

    private var detailsCard: some View {
        GlassCard {
            HStack {
                Label("Expires", systemImage: "calendar")
                Spacer()
                Text(viewModel.profile?.expiresAt?.shortDisplay ?? "Unknown")
                    .foregroundStyle(.secondary)
            }
            .font(.headline)
        }
    }

    private var debugLogCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Connection logs", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Spacer()
                    Button("Clear") {
                        viewModel.clearLogs()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.blue)
                }
                if viewModel.logs.isEmpty {
                    Text("No connection events yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.logs.suffix(12)) { entry in
                            Text(entry.display)
                                .font(.caption.monospaced())
                                .foregroundStyle(entry.level == "error" ? .red : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var connectionText: String {
        switch viewModel.connectionState {
        case .connected: "Connected"
        case .connecting: "Connecting..."
        case .disconnected: "Ready to connect"
        case let .unavailable(message): message
        }
    }
}

#Preview {
    HomeView(viewModel: HomeViewModel(environment: .preview()))
        .environmentObject(AppEnvironment.preview())
}
