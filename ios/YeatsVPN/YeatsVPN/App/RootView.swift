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

            VStack(spacing: 13) {
                header
                statusBlock
                connectButton
                connectionSummaryPanel
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
            iconButton("line.3.horizontal", sheet: .menu)

            Spacer()

            Text("Yeats VPN")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            Spacer()

            iconButton("gearshape", sheet: .settings)
        }
    }

    private var statusBlock: some View {
        VStack(spacing: 10) {
            if let since = viewModel.connectedSince, viewModel.connectionState == .connected {
                ConnectedDurationView(since: since, size: 48)
            } else {
                Text("00:00")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.88))
            }

            statusBadge

            Text(statusSubtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .padding(.top, 18)
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
                    .frame(width: 170, height: 170)
                    .blur(radius: 40)
                    .opacity(glowOpacity)

                ConnectionRings(color: stateColor, isActive: ringsActive)
                    .frame(width: 156, height: 156)

                ZStack {
                    Circle().fill(buttonFill)
                    Circle().fill(DS.glassSheen)
                }
                .frame(width: 122, height: 122)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.2)
                }
                .shadow(color: stateColor.opacity(0.34), radius: 22, y: 12)

                if viewModel.connectionState == .connecting || viewModel.connectionState == .disconnecting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.3)
                } else {
                    Image(systemName: buttonSymbol)
                        .font(.system(size: 36, weight: .bold))
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

    private var connectionSummaryPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "globe.europe.africa.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(stateColor)
                    .frame(width: 42, height: 42)
                    .background(stateColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(serverName)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(serverDetail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text(viewModel.connectionState == .connected ? "Live" : "\(environment.servers.count)")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(viewModel.connectionState == .connected ? .green : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background((viewModel.connectionState == .connected ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
            }

            HStack(spacing: 10) {
                SummaryPill(title: "Used", value: usedTraffic, icon: "arrow.up")
                SummaryPill(title: "Limit", value: trafficLimit, icon: "speedometer")
                SummaryPill(title: "Expires", value: viewModel.profile?.expiresAt?.shortDisplay ?? "-", icon: "calendar")
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 28, strokeOpacity: 0.9)
        .padding(.top, 6)
    }

    private var currentServer: ServerConfig? {
        guard viewModel.connectionState == .connected,
              let location = viewModel.profile?.nodeLocation, !location.isEmpty else {
            return nil
        }
        return environment.servers.first { server in
            server.name.localizedCaseInsensitiveContains(location)
                || location.localizedCaseInsensitiveContains(server.name)
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: MainSheet) -> some View {
        switch sheet {
        case .menu:
            MainMenuSheet(activeSheet: $activeSheet)
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
        case .connected: "Encrypted tunnel is running"
        case .connecting: "Setting up secure tunnel"
        case .disconnecting: "Closing secure tunnel"
        case .disconnected: "Tap power to connect"
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

    private var serverDetail: String {
        guard let server = currentServer ?? environment.servers.first else {
            return "No server loaded"
        }
        return "\(server.proto.rawValue.uppercased()) • \(server.address):\(server.port)"
    }
}

private struct ConnectedDurationView: View {
    let since: Date
    var size: CGFloat = 19

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(duration(from: since, to: context.date))
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.92))
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

private struct SummaryPill: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.55), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private enum MainSheet: String, Identifiable {
    case menu
    case settings
    case help

    var id: String { rawValue }

    var detents: Set<PresentationDetent> {
        switch self {
        case .menu:
            [.medium]
        case .settings:
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
