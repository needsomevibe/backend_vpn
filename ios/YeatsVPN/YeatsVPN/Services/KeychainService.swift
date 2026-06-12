import Foundation
import KeychainAccess

protocol KeychainServicing: Sendable {
    func save(_ value: String, for key: String) throws
    func read(_ key: String) throws -> String?
    func delete(_ key: String) throws
}

final class KeychainService: KeychainServicing, @unchecked Sendable {
    private let keychain = Keychain(service: "uz.yeats.vpn")
        .accessibility(.afterFirstUnlockThisDeviceOnly)

    func save(_ value: String, for key: String) throws {
        try keychain.set(value, key: key)
    }

    func read(_ key: String) throws -> String? {
        try keychain.get(key)
    }

    func delete(_ key: String) throws {
        try keychain.remove(key)
    }
}
