import CryptoKit
import Foundation

/// 저장 파일의 봉투. 안에 든 것은 지금까지와 똑같은 `AccountStorage` JSON이다.
///
/// 이 타입은 파일도 Keychain도 모른다 — `Data`를 받아 `Data`를 돌려준다.
/// 그래야 암호화 자체를 파일시스템 없이 테스트할 수 있다.
enum VaultCrypto {

    static let currentVersion = "2"
    static let legacyVersion = "1.0"

    /// 봉투. `accountCount`는 키 없이 읽어야 하므로 평문으로 둔다
    /// (`StorageService.inspectFile`이 저장 위치 변경 UI에서 쓴다).
    struct Envelope: Codable, Equatable {
        var version: String
        var accountCount: Int
        /// `AES.GCM.SealedBox.combined` — nonce·암호문·인증태그가 한 덩어리.
        /// 셋을 따로 저장하면 태그를 빠뜨리는 실수가 가능한데, 이러면 그 경로가 없다.
        var sealed: Data
    }

    enum Format: Equatable {
        case v1Plaintext
        case v2(Envelope)
    }

    enum VaultError: LocalizedError, Equatable {
        case unknownVersion(String)
        case malformed
        case decryptionFailed

        var errorDescription: String? {
            switch self {
            case .unknownVersion(let v): return "알 수 없는 저장 형식입니다 (version \(v)). 더 새 버전의 앱이 만든 파일일 수 있습니다."
            case .malformed:             return "계정 파일을 읽을 수 없습니다."
            case .decryptionFailed:      return "계정 파일을 복호화하지 못했습니다."
            }
        }
    }

    private struct VersionProbe: Decodable { let version: String }

    static func newKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    static func detect(_ data: Data) throws -> Format {
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else {
            throw VaultError.malformed
        }
        switch probe.version {
        case legacyVersion:
            return .v1Plaintext
        case currentVersion:
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
                throw VaultError.malformed
            }
            return .v2(envelope)
        default:
            // 모르는 형식을 "빈 계정"으로 처리하면 그 위에 저장하는 순간 데이터가 사라진다.
            throw VaultError.unknownVersion(probe.version)
        }
    }

    static func seal(plaintext: Data, accountCount: Int, key: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key))
        guard let combined = box.combined else { throw VaultError.malformed }
        let envelope = Envelope(version: currentVersion, accountCount: accountCount, sealed: combined)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    static func open(_ envelope: Envelope, key: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.sealed)
            return try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            // 키가 틀렸든 변조됐든 사용자에게는 같은 상황이다.
            throw VaultError.decryptionFailed
        }
    }
}
