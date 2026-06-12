import SwiftUI

struct ProfileView: View {
    @StateObject var viewModel: ProfileViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    GlassCard {
                        VStack(spacing: 14) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 70))
                                .foregroundStyle(DS.blue)
                            Text(viewModel.user?.email ?? "Signed in")
                                .font(.title3.bold())
                            StatusPill(
                                text: viewModel.user?.subscription?.status.lowercased() ?? "unknown",
                                isActive: ["ACTIVE", "TRIALING"].contains(viewModel.user?.subscription?.status ?? "")
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }

                    GlassCard {
                        VStack(spacing: 16) {
                            row(title: "Plan", value: viewModel.user?.subscription?.plan?.name ?? "Free")
                            row(title: "Devices", value: "\(viewModel.user?.subscription?.plan?.deviceLimit ?? 1)")
                            row(title: "Expires", value: viewModel.user?.subscription?.expiresAt?.shortDisplay ?? "Unknown")
                        }
                    }

                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error)
                    }

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
                .padding(20)
            }
            .refreshable { await viewModel.refresh() }
            .background(DS.background)
            .navigationTitle("Profile")
            .task { await viewModel.refresh() }
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    ProfileView(viewModel: ProfileViewModel(environment: .preview()))
        .environmentObject(AppEnvironment.preview())
}
