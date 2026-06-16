import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject var viewModel: HomeViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    connectionCard
                    trafficCard
                    infoRow
                    serverCard
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

    // MARK: - Connection Card

    private var connectionCard: some View {
        GlassCard {
            VStack(spacing: 22) {
                HStack {
                    ConnectionStatusPill(state: viewModel.connectionState)
                    Spacer()
                    if let location = viewModel.profile?.nodeLocation {
                        Label(location, systemImage: "location.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                powerButton
                connectionInfo
            }
        }
    }

    private var powerButton: some View {
        Button {
            Task { await viewModel.connectTapped() }
        } label: {
            ZStack {
                // Pulse ring when connecting
                if viewModel.connectionState == .connecting {
                    Circle()
                        .stroke(DS.blue.opacity(0.3), lineWidth: 3)
                        .frame(width: 190, height: 190)
                        .scaleEffect(1.15)
                        .opacity(0.5)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: viewModel.connectionState)
                }
                Circle()
                    .fill(buttonGradient)
                    .frame(width: 172, height: 172)
                    .shadow(color: buttonShadowColor.opacity(0.28), radius: 30, y: 18)
                if viewModel.connectionState == .connecting || viewModel.connectionState == .disconnecting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.5)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 58, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.connectionState == .connecting || viewModel.connectionState == .disconnecting)
    }

    private var connectionInfo: some View {
        VStack(spacing: 6) {
            Text(connectionText)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let since = viewModel.connectedSince, viewModel.connectionState == .connected {
                ConnectionTimer(since: since)
            }
        }
    }

    // MARK: - Traffic Card

    private var trafficCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Traffic", systemImage: "arrow.up.arrow.down")
                        .font(.headline)
                    Spacer()
                    Text("\((viewModel.profile?.trafficUsedGb ?? 0).gbDisplay) / \((viewModel.profile?.trafficLimitGb ?? 0).gbDisplay)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: viewModel.progress)
                    .tint(progressColor)
                    .scaleEffect(y: 1.6)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Info Row

    private var infoRow: some View {
        HStack(spacing: 12) {
            InfoPill(icon: "calendar", title: "Expires", value: viewModel.profile?.expiresAt?.shortDisplay ?? "—")
            InfoPill(icon: "antenna.radiowaves.left.and.right", title: "Status", value: viewModel.profile?.status.capitalized ?? "—")
        }
    }

    // MARK: - Server Card

    private var serverCard: some View {
        Group {
            if !environment.servers.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Servers", systemImage: "server.rack")
                                .font(.headline)
                            Spacer()
                            Text("\(environment.servers.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(environment.servers.prefix(5)) { server in
                            HStack {
                                Text(server.displayName)
                                    .font(.subheadline)
                                Spacer()
                                Text(server.proto.rawValue.uppercased())
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(DS.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(DS.blue.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Debug Log Card

    private var debugLogCard: some View {
        GlassCard {
            DisclosureGroup {
                if viewModel.logs.isEmpty {
                    Text("No connection events yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.logs.suffix(60)) { entry in
                            Text(entry.display)
                                .font(.caption.monospaced())
                                .foregroundStyle(entry.level == "error" ? .red : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 4)
                }
            } label: {
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
            }
        }
    }

    // MARK: - Computed

    private var connectionText: String {
        switch viewModel.connectionState {
        case .connected: "Connected"
        case .connecting: "Connecting..."
        case .disconnecting: "Disconnecting..."
        case .disconnected: "Ready to connect"
        case let .unavailable(message): message
        }
    }

    private var buttonGradient: LinearGradient {
        switch viewModel.connectionState {
        case .connected:
            LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .connecting, .disconnecting:
            LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            LinearGradient(colors: [DS.blue, DS.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var buttonShadowColor: Color {
        switch viewModel.connectionState {
        case .connected: .green
        case .connecting, .disconnecting: .orange
        default: DS.blue
        }
    }

    private var progressColor: Color {
        viewModel.progress > 0.85 ? .red : (viewModel.progress > 0.6 ? .orange : DS.blue)
    }
}

// MARK: - Supporting Views

struct ConnectionTimer: View {
    let since: Date
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formattedElapsed)
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(DS.blue)
            .onReceive(timer) { _ in
                elapsed = Date().timeIntervalSince(since)
            }
            .onAppear {
                elapsed = Date().timeIntervalSince(since)
            }
    }

    private var formattedElapsed: String {
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct ConnectionStatusPill: View {
    let state: VPNConnectionState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(dotColor.opacity(0.12), in: Capsule())
    }

    private var label: String {
        switch state {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnecting: "Disconnecting"
        case .disconnected: "Disconnected"
        case .unavailable: "Unavailable"
        }
    }

    private var dotColor: Color {
        switch state {
        case .connected: .green
        case .connecting, .disconnecting: .orange
        case .disconnected: .secondary
        case .unavailable: .red
        }
    }
}

struct InfoPill: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        GlassCard {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(DS.blue)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    HomeView(viewModel: HomeViewModel(environment: .preview()))
        .environmentObject(AppEnvironment.preview())
}
