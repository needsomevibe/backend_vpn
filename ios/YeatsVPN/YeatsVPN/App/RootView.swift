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

            ScrollView {
                VStack(spacing: 16) {
                    header
                    statusBlock
                    connectButton
                    metricsGrid
                    serversSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.refresh() }
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
                iconButton("gearshape", sheet: .settings)
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

    @ViewBuilder
    private var serversSection: some View {
        if !environment.servers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Locations")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text("\(environment.servers.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(environment.servers) { server in
                            ServerCard(server: server, isCurrent: isCurrentServer(server))
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func isCurrentServer(_ server: ServerConfig) -> Bool {
        guard viewModel.connectionState == .connected,
              let location = viewModel.profile?.nodeLocation, !location.isEmpty else {
            return false
        }
        return server.name.localizedCaseInsensitiveContains(location)
            || location.localizedCaseInsensitiveContains(server.name)
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

private struct ServerCard: View {
    let server: ServerConfig
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "globe")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isCurrent ? .green : DS.blue)
                    .frame(width: 30, height: 30)
                    .background((isCurrent ? Color.green : DS.blue).opacity(0.12), in: Circle())
                Spacer()
                if isCurrent {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(server.displayName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(isCurrent ? "Active" : server.proto.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isCurrent ? .green : .secondary)
            }
        }
        .padding(14)
        .frame(width: 150, height: 96, alignment: .leading)
        .glassSurface(cornerRadius: DS.tileRadius, strokeOpacity: 0.8)
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: DS.tileRadius, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.5), lineWidth: 1.5)
            }
        }
    }
}

private enum MainSheet: String, Identifiable {
    case menu
    case profile
    case settings
    case help

    var id: String { rawValue }

    var detents: Set<PresentationDetent> {
        switch self {
        case .menu:
            [.medium]
        case .profile, .settings:
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
                    present(.help)
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
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

private struct HelpSheet: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label("Tap the switch to connect or disconnect.", systemImage: "power")
                Label("Swipe the Locations row to browse available servers.", systemImage: "server.rack")
                Label("Pull down on the main screen to refresh your status.", systemImage: "arrow.clockwise")
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
