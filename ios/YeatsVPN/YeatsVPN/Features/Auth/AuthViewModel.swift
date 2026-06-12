import Foundation
import AuthenticationServices

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var canLogin: Bool {
        email.contains("@") && password.count >= 8
    }

    var canRegister: Bool {
        canLogin && password == confirmPassword
    }

    func login() async {
        guard canLogin else {
            errorMessage = "Enter a valid email and password."
            return
        }
        await perform {
            try await environment.authService.login(email: email, password: password)
        }
    }

    func register() async {
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        guard canRegister else {
            errorMessage = "Use a valid email and at least 8 characters."
            return
        }
        await perform {
            try await environment.authService.register(email: email, password: password)
        }
    }

    func loginWithApple(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                throw APIError.unauthorized
            }
            let authorizationCode = credential.authorizationCode.flatMap {
                String(data: $0, encoding: .utf8)
            }
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let response = try await environment.authService.loginWithApple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: fullName.isEmpty ? nil : fullName
            )
            environment.handleAuthenticated(response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ action: () async throws -> AuthResponse) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await action()
            environment.handleAuthenticated(response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
