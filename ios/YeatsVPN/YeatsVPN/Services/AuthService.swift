import Foundation

protocol AuthServicing: AuthRefreshing, Sendable {
    func register(email: String, password: String) async throws -> AuthResponse
    func login(email: String, password: String) async throws -> AuthResponse
    func loginWithApple(identityToken: String, authorizationCode: String?, fullName: String?) async throws -> AuthResponse
    func refreshSession() async throws -> AuthResponse
    func me() async throws -> UserProfile
    func logout() async
}

final class AuthService: AuthServicing, @unchecked Sendable {
    private let apiClient: APIClient
    private let tokenStore: TokenStoring
    private let deviceID: DeviceIDServicing

    init(apiClient: APIClient, tokenStore: TokenStoring, deviceID: DeviceIDServicing = DeviceIDService()) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
        self.deviceID = deviceID
    }

    func register(email: String, password: String) async throws -> AuthResponse {
        let response: AuthResponse = try await apiClient.request(
            .register,
            body: RegisterRequest(email: email, password: password, deviceId: deviceID.deviceId)
        )
        try await tokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        return response
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let response: AuthResponse = try await apiClient.request(
            .login,
            body: LoginRequest(email: email, password: password, deviceId: deviceID.deviceId)
        )
        try await tokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        return response
    }

    func loginWithApple(identityToken: String, authorizationCode: String?, fullName: String?) async throws -> AuthResponse {
        let response: AuthResponse = try await apiClient.request(
            .apple,
            body: AppleLoginRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                deviceId: deviceID.deviceId,
                fullName: fullName
            )
        )
        try await tokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        return response
    }

    func refreshSession() async throws -> AuthResponse {
        guard let refreshToken = await tokenStore.refreshToken() else {
            throw APIError.missingToken
        }
        let response: AuthResponse = try await apiClient.request(
            .refresh,
            body: RefreshRequest(refreshToken: refreshToken)
        )
        try await tokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        return response
    }

    func me() async throws -> UserProfile {
        try await apiClient.request(.me)
    }

    func logout() async {
        await tokenStore.clear()
    }
}
