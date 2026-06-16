import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @StateObject var viewModel: AuthViewModel
    @State private var appear = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)

            ZStack {
                Circle()
                    .fill(DS.blue)
                    .frame(width: 170, height: 170)
                    .blur(radius: 60)
                    .opacity(0.4)
                LogoMark(size: 86)
            }

            VStack(spacing: 10) {
                Text("Welcome")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Sign in with Apple to manage your private VPN access.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 24)

            VStack(spacing: 16) {
                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    Task { await viewModel.loginWithApple(result: result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    if viewModel.isLoading {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isLoading)
                .allowsHitTesting(!viewModel.isLoading)

                Text("Your account is created automatically on first sign-in. No email or password required.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 16)
        .background(AmbientBackground())
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
