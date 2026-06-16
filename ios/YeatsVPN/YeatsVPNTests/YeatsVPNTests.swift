import XCTest
@testable import YeatsVPN

final class YeatsVPNTests: XCTestCase {
    func testVPNProfileFallbackFromAccount() {
        let account = VPNAccount(
            id: "vpn",
            remnawaveUuid: "remote",
            remnawaveShortUuid: "short",
            username: "user",
            status: "ACTIVE",
            trafficLimitBytes: "107374182400",
            usedTrafficBytes: "1073741824",
            expiresAt: nil,
            subscriptionUrl: "https://sub.yeats.uz/short"
        )

        let profile = VPNProfile(account: account)

        XCTAssertEqual(profile.status, "active")
        XCTAssertEqual(profile.trafficUsedGb, 1)
        XCTAssertEqual(profile.trafficLimitGb, 100)
        XCTAssertEqual(profile.subscriptionUrl, "https://sub.yeats.uz/short")
    }

    func testVPNProfileAppliesUsageResponse() {
        let profile = VPNProfile(
            status: "active",
            subscriptionUrl: "https://sub.yeats.uz/short",
            trafficUsedGb: 0,
            trafficLimitGb: 100,
            expiresAt: nil,
            nodeLocation: nil
        )
        let usage = VPNUsage(
            usedTrafficBytes: "3221225472",
            usedTrafficGb: 3,
            trafficLimitBytes: "107374182400",
            trafficLimitGb: 100,
            nodeLocation: "DE"
        )

        let updated = profile.applying(usage: usage)

        XCTAssertEqual(updated.trafficUsedGb, 3)
        XCTAssertEqual(updated.trafficLimitGb, 100)
        XCTAssertEqual(updated.nodeLocation, "DE")
        XCTAssertEqual(updated.subscriptionUrl, profile.subscriptionUrl)
    }

    func testTokenStorePersistsTokens() async throws {
        let keychain = MockKeychainService()
        let store = TokenStore(keychain: keychain)

        try await store.save(accessToken: "access", refreshToken: "refresh")

        let accessToken = await store.accessToken()
        let refreshToken = await store.refreshToken()
        let hasRefreshToken = await store.hasRefreshToken()

        XCTAssertEqual(accessToken, "access")
        XCTAssertEqual(refreshToken, "refresh")
        XCTAssertTrue(hasRefreshToken)

        await store.clear()
        let clearedAccessToken = await store.accessToken()
        XCTAssertNil(clearedAccessToken)
    }
}

final class MockKeychainService: KeychainServicing, @unchecked Sendable {
    private var values: [String: String] = [:]

    func save(_ value: String, for key: String) throws {
        values[key] = value
    }

    func read(_ key: String) throws -> String? {
        values[key]
    }

    func delete(_ key: String) throws {
        values.removeValue(forKey: key)
    }
}
