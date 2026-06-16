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
    @State private var isPressed = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 30)
                statusBlock
                Spacer(minLength: 24)
                connectButton
                Spacer(minLength: 28)
                metricsGrid
                Spacer(minLength: 18)
                quickActions
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 18)
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
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Yeats VPN")
                    .font(.title2.weight(.bold))
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                iconButton("list.bullet.rectangle", sheet: .logs)
                iconButton("ellipsis", sheet: .menu)
            }
        }
    }

    private var statusBlock: some View {
        VStack(spacing: 12) {
            statusBadge

            Text(statusTitle)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .contentTransition(.opacity)

            Text(statusSubtitle)
                .font(.body.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280)

            if let since = viewModel.connectedSince, viewModel.connectionState == .connected {
                ConnectedDurationView(since: since)
                    .padding(.top, 4)
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(statusTitle.uppercased())
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(stateColor)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(stateColor.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(stateColor.opacity(0.18), lineWidth: 1)
        }
    }

    private var connectButton: some View {
        Button {
            Task { await viewModel.connectTapped() }
        } label: {
            ZStack {
                Circle()
                    .fill(buttonFill)
                    .frame(width: 194, height: 194)
                    .shadow(color: stateColor.opacity(viewModel.connectionState == .disconnected ? 0.14 : 0.28), radius: 34, y: 18)

                Circle()
                    .strokeBorder(.white.opacity(0.34), lineWidth: 1)
                    .frame(width: 194, height: 194)

                if viewModel.connectionState == .connecting || viewModel.connectionState == .disconnecting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.45)
                } else {
                    Image(systemName: buttonSymbol)
                        .font(.system(size: 58, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: viewModel.connectionState == .connected)
                }
            }
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(.smooth(duration: 0.18), value: isPressed)
            .animation(.snappy(duration: 0.32), value: viewModel.connectionState)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.connectionState == .connecting || viewModel.connectionState == .disconnecting)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private var metricsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MetricTile(
                    title: "Traffic",
                    value: usedTraffic,
                    footnote: trafficLimit,
                    icon: "arrow.up.arrow.down",
                    tint: DS.blue
                ) {
                    activeSheet = .logs
                }
                MetricTile(
                    title: "Server",
                    value: serverName,
                    footnote: environment.servers.isEmpty ? "No servers" : "\(environment.servers.count) available",
                    icon: "server.rack",
                    tint: .purple
                ) {
                    activeSheet = .servers
                }
            }

            HStack(spacing: 12) {
                MetricTile(
                    title: "Expires",
                    value: viewModel.profile?.expiresAt?.shortDisplay ?? "-",
                    footnote: "Subscription",
                    icon: "calendar",
                    tint: .orange
                ) {
                    activeSheet = .profile
                }
                MetricTile(
                    title: "Status",
                    value: statusTitle,
                    footnote: viewModel.profile?.status.capitalized ?? "VPN",
                    icon: "shield.lefthalf.filled",
                    tint: stateColor
                ) {
                    activeSheet = .help
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                activeSheet = .servers
            } label: {
                Label("Servers", systemImage: "server.rack")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
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

    private func iconButton(_ systemImage: String, sheet: MainSheet) -> some View {
        Button {
            activeSheet = sheet
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var stateColor: Color {
        switch viewModel.connectionState {
        case .connected:
            .green
        case .connecting, .disconnecting:
            .orange
        case .unavailable:
            .red
        case .disconnected:
            DS.blue
        }
    }

    private var buttonFill: LinearGradient {
        switch viewModel.connectionState {
        case .connected:
            LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .connecting, .disconnecting:
            LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .unavailable:
            LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .disconnected:
            LinearGradient(colors: [DS.blue, DS.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var buttonSymbol: String {
        switch viewModel.connectionState {
        case .connected:
            "checkmark.shield.fill"
        case .unavailable:
            "exclamationmark.triangle.fill"
        default:
            "power"
        }
    }

    private var headerSubtitle: String {
        switch viewModel.connectionState {
        case .connected:
            "Secure tunnel running"
        case .connecting:
            "Preparing connection"
        case .disconnecting:
            "Stopping connection"
        case .disconnected:
            "Ready when you are"
        case .unavailable:
            "Needs attention"
        }
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
        case .connected: "Your connection is private and routed through Yeats VPN."
        case .connecting: "Setting up the secure tunnel."
        case .disconnecting: "Closing the tunnel cleanly."
        case .disconnected: "Tap the button to protect your connection."
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

private struct ConnectedDurationView: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(duration(from: since, to: context.date))
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.blue)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.2), value: duration(from: since, to: context.date))
        }
        .accessibilityLabel("Connected for")
    }

    private func duration(from start: Date, to end: Date) -> String {
        let elapsed = max(0, Int(end.timeIntervalSince(start)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let footnote: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundStyle(tint)
                        .frame(width: 30, height: 30)
                        .background(tint.opacity(0.12), in: Circle())
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
