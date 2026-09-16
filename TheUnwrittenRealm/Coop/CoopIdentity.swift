import Foundation

#if canImport(Security)
import Security
#endif

public struct CoopInstallationIdentity: Codable, Equatable, Sendable {
    public let installationID: UUID
    public let publicKeyData: Data

    public init(service: String = "com.acwilan.TheUnwrittenRealm.coop-identity") throws {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecMatchLimit as String: kSecMatchLimitOne, kSecReturnData as String: true]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
           let stored = try? JSONDecoder().decode(StoredIdentity.self, from: data) {
            installationID = stored.installationID; publicKeyData = stored.publicKeyData; return
        }
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeySizeInBits as String: 256]
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error), let publicKey = SecKeyCopyPublicKey(privateKey), let publicData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?, let privateData = SecKeyCopyExternalRepresentation(privateKey, nil) as Data? else { throw IdentityError.keyGenerationFailed }
        let stored = StoredIdentity(installationID: UUID(), publicKeyData: publicData, privateKeyData: privateData)
        let data = try JSONEncoder().encode(stored)
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw IdentityError.keychainFailed }
        installationID = stored.installationID; publicKeyData = stored.publicKeyData
        #else
        throw IdentityError.securityFrameworkUnavailable
        #endif
    }

    public var verificationCode: String { String(installationID.uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased() }
}

private struct StoredIdentity: Codable {
    let installationID: UUID
    let publicKeyData: Data
    let privateKeyData: Data?
}

public enum IdentityError: Error, Equatable, Sendable { case keyGenerationFailed; case keychainFailed; case securityFrameworkUnavailable }
