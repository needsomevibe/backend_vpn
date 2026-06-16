import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()
            switch environment.route {
            case .splash:
                SplashView()
            case .login:
                LoginView(viewModel: AuthViewModel(environment: environment))
            case .register:
                RegisterView(viewModel: AuthViewModel(environment: environment))
            case .main:
                MainVPNView(viewModel: HomeViewModel(environment: environment))
            }
        }
        .animation(.snappy(duration: 0.28), value: environment.route)
    }
}

struct MainVPNView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject var viewModel: HomeViewModel
    @State private var activeSheet: MainSheet?

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 28)
                brand
                Spacer(minLength: 44)
                connectionToggle
                statusCopy
                Spacer(minLength: 28)
                detailsPanel
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
        }
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
        .sheet(item: $activeSheet) { sheet in
            sheetView(sheet)
                .presentationDetents(sheet.detents)
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Yeats")
                    .font(.system(size: 34, weight: .black))
                Text("VPN")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 16) {
                iconButton("terminal.fill", sheet: .logs)
                iconButton("questionmark.circle", sheet: .help)
                iconButton("line.3.horizontal", sheet: .menu)
            }
        }
    }

    private var brand: some View {
        VStack(spacing: 16) {
            Text("YEATS")
                .font(.system(size: 70, weight: .black))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.red, .orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            if viewModel.connectionState == .connected {
                Text("Private tunnel is active.")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            } else {
                Text("Your Internet is not private.")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var connectionToggle: some View {
        Button {
            Task { await viewModel.connectTapped() }
        } label: {
            ZStack(alignment: toggleAlignment) {
                Capsule()
                    .fill(toggleTrack)
                    .frame(width: 222, height: 112)
                    .shadow(color: toggleShadow.opacity(0.18), radius: 22, y: 12)

                Circle()
                    .fill(Color(uiColor: .systemBackground))
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
                    .overlay {
                        if viewModel.connectionState == .connecting || viewModel.connectionState == .disconnecting {
                            ProgressView()
                                .tint(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
            }
            .frame(width: 222, height: 112)
            .animation(.snappy(duration: 0.28), value: viewModel.connectionState)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.connectionState == .connecting || viewModel.connectionState == .disconnecting)
    }

    private var statusCopy: some View {
        VStack(spacing: 8) {
            Text(statusTitle)
                .font(.system(size: 28, weight: .black))
            if let since = viewModel.connectedSince, viewModel.connectionState == .connected {
                ConnectionTimer(since: since)
            } else {
                Text(statusSubtitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 18)
    }

    private var detailsPanel: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(width: 42, height: 5)

            HStack {
                detailButton(
                    title: "Traffic",
                    value: "\(usedTraffic) / \(trafficLimit)",
                    icon: "arrow.up.arrow.down",
                    sheet: .logs
                )
                Divider().frame(height: 42)
                detailButton(
                    title: "Server",
                    value: serverName,
                    icon: "server.rack",
                    sheet: .servers
                )
                Divider().frame(height: 42)
                detailButton(
                    title: "Expires",
                    value: viewModel.profile?.expiresAt?.shortDisplay ?? "-",
                    icon: "calendar",
                    sheet: .profile
                )
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.12), radius: 28, y: -8)
        )
    }

    private func iconButton(_ systemImage: String, sheet: MainSheet) -> some View {
        Button {
            activeSheet = sheet
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }

    private func detailButton(title: String, value: String, icon: String, sheet: MainSheet) -> some View {
        Button {
            activeSheet = sheet
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sheetView(_ sheet: MainSheet) -> some View {
        switch sheet {
        case .menu:
            MainMenuSheet(activeSheet: $activeSheet)
                .environmentObject(environment)
        case .profile:
            ProfileView(viewModel: ProfileViewModel(environment: environment))
                .environmentObject(environment)
        case .settings:
            SettingsView()
                .environmentObject(environment)
        case .servers:
            ServersSheet(servers: environment.servers)
        case .logs:
            LogsSheet(logs: viewModel.logs) {
                viewModel.clearLogs()
            }
        case .help:
            HelpSheet()
        }
    }

    private var toggleAlignment: Alignment {
        viewModel.connectionState == .connected ? .trailing : .leading
    }

    private var toggleTrack: Color {
        switch viewModel.connectionState {
        case .connected:
            .green.opacity(0.82)
        case .connecting, .disconnecting:
            .orange.opacity(0.30)
        case .unavailable:
            .red.opacity(0.24)
        case .disconnected:
            Color(uiColor: .systemGray5)
        }
    }

    private var toggleShadow: Color {
        viewModel.connectionState == .connected ? .green : .black
    }

    private var statusTitle: String {
        switch viewModel.connectionState {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnecting: "Disconnecting"
        case .disconnected: "Disconnected"
        case .unavailable: "Unavailable"
        }
    }

    private var statusSubtitle: String {
        switch viewModel.connectionState {
        case .connected: "Your traffic is protected."
        case .connecting: "Starting secure tunnel..."
        case .disconnecting: "Closing secure tunnel..."
        case .disconnected: "Tap the switch to connect."
        case let .unavailable(message): message
        }
    }

    private var usedTraffic: String {
        (viewModel.profile?.trafficUsedGb ?? 0).gbDisplay
    }

    private var trafficLimit: String {
        (viewModel.profile?.trafficLimitGb ?? 0).gbDisplay
    }

    private var serverName: String {
        if let location = viewModel.profile?.nodeLocation, !location.isEmpty {
            return location
        }
        return environment.servers.first?.displayName ?? "-"
    }
}

private enum MainSheet: String, Identifiable {
    case menu
    case profile
    case settings
    case servers
    case logs
    case help

    var id: String { rawValue }

    var detents: Set<PresentationDetent> {
        switch self {
        case .menu:
            [.medium]
        case .servers, .logs, .profile, .settings:
            [.medium, .large]
        case .help:
            [.fraction(0.34), .medium]
        }
    }
}

private struct MainMenuSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Binding var activeSheet: MainSheet?

    var body: some View {
        NavigationStack {
            List {
                Button {
                    present(.profile)
                } label: {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                Button {
                    present(.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button {
                    present(.servers)
                } label: {
                    Label("Servers", systemImage: "server.rack")
                }
                Button {
                    present(.logs)
                } label: {
                    Label("Connection Logs", systemImage: "list.bullet.rectangle")
                }
                Button(role: .destructive) {
                    dismiss()
                    Task { await environment.logout() }
                } label: {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func present(_ sheet: MainSheet) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            activeSheet = sheet
        }
    }
}

private struct ServersSheet: View {
    let servers: [ServerConfig]

    var body: some View {
        NavigationStack {
            List {
                if servers.isEmpty {
                    ContentUnavailableView("No Servers", systemImage: "server.rack")
                } else {
                    ForEach(servers) { server in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.displayName)
                                .font(.headline)
                            Text("\(server.address):\(server.port)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(server.proto.rawValue.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(DS.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Servers")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct LogsSheet: View {
    let logs: [DebugLogEntry]
    let clear: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if logs.isEmpty {
                    ContentUnavailableView("No Logs", systemImage: "list.bullet.rectangle")
                } else {
                    ForEach(logs.suffix(80)) { entry in
                        Text(entry.display)
                            .font(.caption.monospaced())
                            .foregroundStyle(entry.level == "error" ? .red : .secondary)
                    }
                }
            }
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear", action: clear)
                }
            }
        }
    }
}

private struct HelpSheet: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label("Tap the switch to connect or disconnect.", systemImage: "power")
                Label("Open Servers to inspect available locations.", systemImage: "server.rack")
                Label("Connection diagnostics live in Logs.", systemImage: "list.bullet.rectangle")
                Spacer()
            }
            .font(.subheadline.weight(.semibold))
            .padding(24)
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppEnvironment.preview())
}
