import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ZStack {
            AmbientBackground()
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
            AmbientBackground(tint: stateColor)

            VStack(spacing: 14) {
                header
                statusBlock
                connectButton
                metricsGrid
                quickActions
            }
            .padding(.horizontal, 18)
            .padding(.top, 50)
            .padding(.bottom, 16)
        }
        .task { await viewModel.refresh() }
        .sheet(item: $activeSheet) { sheet in
            sheetView(sheet)
                .presentationDetents(sheet.detents)
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: viewModel.connectionState)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.errorMessage)
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Remna")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(headerSubtitle)
                    .font(.subheadline.weight(.medium))
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
        VStack(spacing: 8) {
            statusBadge

            Text(statusTitle)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .contentTransition(.opacity)

            Text(statusSubtitle)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: 330)

            if let since = viewModel.connectedSince, viewModel.connectionState == .connected {
                ConnectedDurationView(since: since)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
                    .fill(stateColor)
                    .frame(width: 196, height: 196)
                    .blur(radius: 46)
                    .opacity(glowOpacity)

                ConnectionRings(color: stateColor, isActive: ringsActive)
                    .frame(width: 178, height: 178)

                ZStack {
                    Circle().fill(buttonFill)
                    Circle().fill(DS.glassSheen)
                }
                .frame(width: 142, height: 142)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.2)
                }
                .shadow(color: stateColor.opacity(0.38), radius: 26, y: 14)

                if viewModel.connectionState == .connecting || viewModel.connectionState == .disconnecting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.3)
                } else {
                    Image(systemName: buttonSymbol)
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: viewModel.connectionState == .connected)
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1)
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

    private var ringsActive: Bool {
        switch viewModel.connectionState {
        case .connected, .connecting, .disconnecting: true
        default: false
        }
    }

    private var glowOpacity: Double {
        switch viewModel.connectionState {
        case .connected: 0.5
        case .connecting, .disconnecting: 0.4
        case .unavailable: 0.35
        case .disconnected: 0.18
        }
    }

    private var metricsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricTile(
                    title: "Traffic",
                    value: usedTraffic,
                    footnote: trafficLimit,
                    icon: "arrow.up.arrow.down",
                    tint: DS.blue
                )
                MetricTile(
                    title: "Server",
                    value: serverName,
                    footnote: environment.servers.isEmpty ? "No servers" : "\(environment.servers.count) available",
                    icon: "server.rack",
                    tint: .purple
                )
            }

            HStack(spacing: 10) {
                MetricTile(
                    title: "Expires",
                    value: viewModel.profile?.expiresAt?.shortDisplay ?? "-",
                    footnote: "Subscription",
                    icon: "calendar",
                    tint: .orange
                )
                MetricTile(
                    title: "Status",
                    value: statusTitle,
                    footnote: viewModel.profile?.status.capitalized ?? "VPN",
                    icon: "shield.lefthalf.filled",
                    tint: stateColor
                )
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            QuickActionButton(
                title: "Servers",
                icon: "server.rack",
                style: .secondary
            ) {
                activeSheet = .servers
            }

            QuickActionButton(
                title: "Refresh",
                icon: "arrow.clockwise",
                style: .primary,
                isLoading: viewModel.isLoading
            ) {
                Task { await viewModel.refresh() }
            }
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
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().fill(DS.glassSheen) }
                .overlay { Circle().strokeBorder(DS.glassStroke, lineWidth: 1) }
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
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
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())
                Spacer()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .glassSurface(cornerRadius: DS.tileRadius, strokeOpacity: 0.8)
    }
}

private struct QuickActionButton: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    let icon: String
    let style: Style
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(style == .primary ? .white : DS.blue)
                } else {
                    Image(systemName: icon)
                        .font(.headline.weight(.semibold))
                }
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(foreground)
            .background(background)
            .overlay { Capsule().fill(DS.glassSheen) }
            .clipShape(Capsule())
            .overlay { Capsule().strokeBorder(border, lineWidth: 1) }
            .shadow(color: shadow, radius: 14, y: 7)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isLoading)
    }

    private var foreground: Color {
        style == .primary ? .white : DS.blue
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            LinearGradient(colors: [DS.blue, DS.cyan], startPoint: .leading, endPoint: .trailing)
        case .secondary:
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private var border: AnyShapeStyle {
        style == .primary ? AnyShapeStyle(Color.white.opacity(0.25)) : AnyShapeStyle(DS.glassStroke)
    }

    private var shadow: Color {
        style == .primary ? DS.blue.opacity(0.22) : .black.opacity(0.06)
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
            .scrollContentBackground(.hidden)
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
            .scrollContentBackground(.hidden)
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
            .scrollContentBackground(.hidden)
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
