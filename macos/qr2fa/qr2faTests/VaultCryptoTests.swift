import XCTest
@testable import qr2fa

final class VaultCryptoTests: XCTestCase {

    private let plaintext = Data(#"{"version":"1.0","nextId":1,"accounts":[]}"#.utf8)

    func test_roundTrip() throws {
        let key = VaultCrypto.newKey()
        let file = try VaultCrypto.seal(plaintext: plaintext, accountCount: 3, key: key)

        guard case .v2(let envelope) = try VaultCrypto.detect(file) else {
            return XCTFail("v2로 판별되어야 한다")
        }
        XCTAssertEqual(envelope.accountCount, 3)
        XCTAssertEqual(try VaultCrypto.open(envelope, key: key), plaintext)
    }

    func test_newKeyIs32Bytes() {
        XCTAssertEqual(VaultCrypto.newKey().count, 32)
    }

    func test_wrongKeyFails() throws {
        let file = try VaultCrypto.seal(plaintext: plaintext, accountCount: 0, key: VaultCrypto.newKey())
        guard case .v2(let envelope) = try VaultCrypto.detect(file) else { return XCTFail() }

        XCTAssertThrowsError(try VaultCrypto.open(envelope, key: VaultCrypto.newKey())) { error in
            XCTAssertEqual(error as? VaultCrypto.VaultError, .decryptionFailed)
        }
    }

    func test_tamperedSealedFails() throws {
        let key = VaultCrypto.newKey()
        let file = try VaultCrypto.seal(plaintext: plaintext, accountCount: 0, key: key)
        guard case .v2(var envelope) = try VaultCrypto.detect(file) else { return XCTFail() }

        // 마지막 바이트 1비트를 뒤집는다 — 인증 태그가 잡아내야 한다
        var bytes = [UInt8](envelope.sealed)
        bytes[bytes.count - 1] ^= 0x01
        envelope.sealed = Data(bytes)

        XCTAssertThrowsError(try VaultCrypto.open(envelope, key: key)) { error in
            XCTAssertEqual(error as? VaultCrypto.VaultError, .decryptionFailed)
        }
    }

    func test_sameContentEncryptsDifferently() throws {
        let key = VaultCrypto.newKey()
        let a = try VaultCrypto.seal(plaintext: plaintext, accountCount: 0, key: key)
        let b = try VaultCrypto.seal(plaintext: plaintext, accountCount: 0, key: key)
        XCTAssertNotEqual(a, b, "nonce가 매번 새로 뽑혀야 한다")
    }

    func test_detectsV1Plaintext() throws {
        let v1 = Data(#"{"version":"1.0","nextId":0,"accounts":[]}"#.utf8)
        XCTAssertEqual(try VaultCrypto.detect(v1), .v1Plaintext)
    }

    func test_unknownVersionThrows() {
        let future = Data(#"{"version":"9","sealed":"AAAA"}"#.utf8)
        XCTAssertThrowsError(try VaultCrypto.detect(future)) { error in
            XCTAssertEqual(error as? VaultCrypto.VaultError, .unknownVersion("9"))
        }
    }

    func test_garbageThrowsMalformed() {
        XCTAssertThrowsError(try VaultCrypto.detect(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? VaultCrypto.VaultError, .malformed)
        }
    }
}
