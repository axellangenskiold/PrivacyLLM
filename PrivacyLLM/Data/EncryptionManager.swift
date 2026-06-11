import CryptoKit
import Foundation
import Security

nonisolated enum EncryptionError: Error {
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case malformedCiphertext
}

/// AES-GCM encryption for user content at rest (PR-5). The key lives only in
/// the Keychain (PR-6); ciphertext is stored in SQLite BLOBs.
nonisolated struct EncryptionManager: Sendable {
    private let key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }

    /// Random throwaway key for tests, previews, and in-memory databases.
    static func ephemeral() -> EncryptionManager {
        EncryptionManager(key: SymmetricKey(size: .bits256))
    }

    /// Loads the content key from the Keychain, generating it on first launch.
    static func keychainBacked(
        service: String = "com.axellangenskiold.PrivacyLLM",
        account: String = "content-encryption-key"
    ) throws -> EncryptionManager {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        var readQuery = baseQuery
        readQuery[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw EncryptionError.keychainReadFailed(status) }
            return EncryptionManager(key: SymmetricKey(data: data))
        case errSecItemNotFound:
            let key = SymmetricKey(size: .bits256)
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw EncryptionError.keychainWriteFailed(addStatus) }
            return EncryptionManager(key: key)
        default:
            throw EncryptionError.keychainReadFailed(status)
        }
    }

    func encrypt(_ plaintext: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw EncryptionError.malformedCiphertext }
        return combined
    }

    func decrypt(_ ciphertext: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }

    func encrypt(_ string: String) throws -> Data {
        try encrypt(Data(string.utf8))
    }

    func decryptString(_ ciphertext: Data) throws -> String {
        try String(decoding: decrypt(ciphertext), as: UTF8.self)
    }

    func encryptJSON(_ value: some Encodable) throws -> Data {
        try encrypt(JSONEncoder().encode(value))
    }

    func decryptJSON<T: Decodable>(_ type: T.Type, from ciphertext: Data) throws -> T {
        try JSONDecoder().decode(type, from: decrypt(ciphertext))
    }
}
