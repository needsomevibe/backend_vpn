import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject var viewModel: AuthViewModel
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(DS.blue)
                            .frame(width: 150, height: 150)
                            .blur(radius: 55)
                            .opacity(0.4)
                        LogoMark(size: 74)
                    }
                    VStack(spacing: 8) {
                        Text("Welcome back")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
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
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 16)
            }
            .background(AmbientBackground())
        }
        .task {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                appear = true
            }
        }
    }
}

#Preview {
    LoginView(viewModel: AuthViewModel(environment: .preview()))
        .environmentObject(AppEnvironment.preview())
}
