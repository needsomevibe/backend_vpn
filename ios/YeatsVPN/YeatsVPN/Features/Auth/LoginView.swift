import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject var viewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    LogoMark(size: 74)
                    VStack(spacing: 8) {
                        Text("Welcome back")
                            .font(.largeTitle.bold())
                        Text("Sign in to manage your private VPN access.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    GlassCard {
                        VStack(spacing: 14) {
                            FormField(title: "Email", systemImage: "envelope.fill", text: $viewModel.email)
                            FormField(title: "Password", systemImage: "lock.fill", text: $viewModel.password, isSecure: true)
                            if let error = viewModel.errorMessage {
                                ErrorBanner(message: error)
                            }
                            PrimaryButton(title: "Login", systemImage: "arrow.right.circle.fill", isLoading: viewModel.isLoading) {
                                Task { await viewModel.login() }
                            }
                            SignInWithAppleButton(.signIn) { request in
                                request.requestedScopes = [.email, .fullName]
                            } onCompletion: { result in
                                Task { await viewModel.loginWithApple(result: result) }
                            }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    Button("Create account") {
                        environment.route = .register
                    }
                    .font(.headline)
                    .foregroundStyle(DS.blue)
                }
                .padding(24)
            }
            .background(AmbientBackground())
        }
    }
}

#Preview {
    LoginView(viewModel: AuthViewModel(environment: .preview()))
        .environmentObject(AppEnvironment.preview())
}
