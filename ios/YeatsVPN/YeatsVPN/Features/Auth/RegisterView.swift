import SwiftUI
import AuthenticationServices

struct RegisterView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject var viewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    LogoMark(size: 74)
                    VStack(spacing: 8) {
                        Text("Create account")
                            .font(.largeTitle.bold())
                        Text("Start with a secure 100 GB trial profile.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    GlassCard {
                        VStack(spacing: 14) {
                            FormField(title: "Email", systemImage: "envelope.fill", text: $viewModel.email)
                            FormField(title: "Password", systemImage: "lock.fill", text: $viewModel.password, isSecure: true)
                            FormField(title: "Confirm password", systemImage: "checkmark.shield.fill", text: $viewModel.confirmPassword, isSecure: true)
                            if let error = viewModel.errorMessage {
                                ErrorBanner(message: error)
                            }
                            PrimaryButton(title: "Create account", systemImage: "sparkles", isLoading: viewModel.isLoading) {
                                Task { await viewModel.register() }
                            }
                            SignInWithAppleButton(.signUp) { request in
                                request.requestedScopes = [.email, .fullName]
                            } onCompletion: { result in
                                Task { await viewModel.loginWithApple(result: result) }
                            }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    Button("I already have an account") {
                        environment.route = .login
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
    RegisterView(viewModel: AuthViewModel(environment: .preview()))
        .environmentObject(AppEnvironment.preview())
}
