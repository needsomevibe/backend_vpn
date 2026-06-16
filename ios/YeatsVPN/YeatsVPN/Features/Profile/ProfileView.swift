import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject var viewModel: ProfileViewModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    avatarCard
                    subscriptionCard
                    devicesCard
                    accountCard

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    logoutButton
                }
                .padding(20)
            }
            .refreshable { await viewModel.refresh() }
            .background(AmbientBackground())
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(DS.blue)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task { await viewModel.refresh() }
        }
    }

    // MARK: - Avatar Card

    private var avatarCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [DS.blue, DS.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                    Text(initials)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(viewModel.user?.email ?? "Signed in")
                    .font(.title3.bold())
                StatusPill(
                    text: viewModel.subscription?.status.lowercased() ?? "unknown",
                    isActive: ["ACTIVE", "TRIALING"].contains(viewModel.subscription?.status ?? "")
                )
                Text("Member since \(viewModel.memberSince)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Subscription Card

    private var subscriptionCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Label("Subscription", systemImage: "creditcard.fill")
                        .font(.headline)
                    Spacer()
                }
                row(title: "Plan", value: viewModel.plan?.name ?? "Free", icon: "tag.fill")
                row(title: "Traffic", value: "\(viewModel.plan?.trafficLimitGb ?? 0) GB", icon: "arrow.up.arrow.down")
                row(title: "Devices", value: "\(viewModel.plan?.deviceLimit ?? 1)", icon: "iphone.gen3")
                row(title: "Duration", value: "\(viewModel.plan?.durationDays ?? 30) days", icon: "clock.fill")
                row(title: "Expires", value: viewModel.subscription?.expiresAt?.shortDisplay ?? "Unknown", icon: "calendar")
                if let price = viewModel.plan?.priceCents, price > 0 {
                    row(title: "Price", value: "$\(String(format: "%.2f", Double(price) / 100))/mo", icon: "dollarsign.circle.fill")
                } else {
                    row(title: "Price", value: "Free", icon: "dollarsign.circle.fill")
                }
            }
        }
    }

    // MARK: - Devices Card

    private var devicesCard: some View {
        Group {
            if !viewModel.devices.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Devices", systemImage: "iphone.gen3")
                                .font(.headline)
                            Spacer()
                            Text("\(viewModel.devices.count)")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DS.blue.opacity(0.15), in: Capsule())
                        }
                        ForEach(viewModel.devices) { device in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name ?? device.platform.capitalized)
                                        .font(.subheadline.weight(.medium))
                                    Text(device.lastSeenAt?.shortDisplay ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(device.platform.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Account Card

    private var accountCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Label("Account", systemImage: "person.text.rectangle")
                        .font(.headline)
                    Spacer()
                }
                row(title: "Email", value: viewModel.user?.email ?? "—", icon: "envelope.fill")
                row(title: "Status", value: viewModel.user?.status.capitalized ?? "—", icon: "checkmark.shield.fill")
                row(title: "User ID", value: String((viewModel.user?.id ?? "").prefix(8)) + "...", icon: "number")
            }
        }
    }

    // MARK: - Logout Button

    private var logoutButton: some View {
        Button(role: .destructive) {
            Task { await viewModel.logout() }
        } label: {
            Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    // MARK: - Helpers

    private func row(title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(.titleOnly)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private var initials: String {
        let email = viewModel.user?.email ?? "?"
        return String(email.prefix(2)).uppercased()
    }
}

#Preview {
    ProfileView(viewModel: ProfileViewModel(environment: .preview()))
        .environmentObject(AppEnvironment.preview())
}
