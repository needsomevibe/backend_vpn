import Foundation

protocol TokenStoring: Sendable {
    func accessToken() async -> String?
    func refreshToken() async -> String?
    func save(accessToken: String, refreshToken: String) async throws
    func clear() async
    func hasRefreshToken() async -> Bool
}

actor TokenStore: TokenStoring {
    private let keychain: KeychainServicing
    private let accessKey = "accessToken"
    private let refreshKey = "refreshToken"

    init(keychain: KeychainServicing) {
        self.keychain = keychain
    }

    func accessToken() async -> String? {
        try? keychain.read(accessKey)
    }

    func refreshToken() async -> String? {
        try? keychain.read(refreshKey)
    }

    func save(accessToken: String, refreshToken: String) async throws {
        try keychain.save(accessToken, for: accessKey)
        try keychain.save(refreshToken, for: refreshKey)
    }

    func clear() async {
        try? keychain.delete(accessKey)
        try? keychain.delete(refreshKey)
    }

    func hasRefreshToken() async -> Bool {
        await refreshToken() != nil
    }
}
