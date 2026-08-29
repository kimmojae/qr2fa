import Foundation
import Security

/// 저장 파일을 여는 32바이트 키를 어디에 두는지.
///
/// 프로토콜로 둔 이유는 테스트다. 실제 Keychain을 건드리는 테스트는 이 맥의 상태에
/// 결과가 좌우되고, 최악의 경우 개발자 본인의 항목을 지운다.
/// `StorageServiceTests`가 `defaults`를 주입받는 것과 같은 이유다.
protocol KeyStore {
    /// 키가 없으면 nil. 조회 자체가 실패하면 throw.
    func load() throws -> Data?
    func save(_ key: Data) throws
}

final class InMemoryKeyStore: KeyStore {
    private var key: Data?
    init(key: Data? = nil) { self.key = key }
    func load() throws -> Data? { key }
    func save(_ key: Data) throws { self.key = key }
}

final class KeychainKeyStore: KeyStore {

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return "Keychain 오류 (\(status))"
            }
        }
    }

    private let service: String
    private let account: String

    init(service: String = "com.kimmojae.qr2fa", account: String = "vault-key") {
        self.service = service
        self.account = account
    }

    /// 로컬 Keychain에만 저장한다.
    ///
    /// `kSecAttrSynchronizable`을 켜서 iCloud Keychain이 이 키를 다른 Mac에 나눠주게
    /// 하고 싶었지만(저장 위치로 iCloud Drive를 고른 사용자가 Mac을 바꿨을 때 파일은
    /// 따라오는데 키가 없어서 잠기는 문제를 막으려는 의도), 실제 기기에서
    /// `errSecMissingEntitlement (-34018)`로 거부됨을 확인했다 — 이 플래그는 Apple
    /// Developer ID로 서명된 앱만 쓸 수 있고, 지금은 자체 서명(`qr2fa-selfsign`)이다.
    /// Developer ID를 받으면(하위 프로젝트 4) 다시 켠다. 그 전까지는 저장 위치를
    /// 여러 Mac에서 각자 온보딩해야 한다 — 이미 `StorageService`가 정상 시나리오로
    /// 다루는 경로다.
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue as Any
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed, errSecUserCanceled, errSecAuthFailed:
            // 사용자가 Keychain 접근을 거부했거나 화면이 잠겨 있다. 키가 "없는" 것으로
            // 다뤄서 잠금 상태로 떨어뜨린다 — 앱이 죽는 것보다 낫다.
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func save(_ key: Data) throws {
        let update: [String: Any] = [kSecValueData as String: key]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var insert = baseQuery
            insert[kSecValueData as String] = key
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
