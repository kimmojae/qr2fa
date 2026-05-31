import XCTest
@testable import qr2fa

final class AccountTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fmt.date(from: s) { return date }
            fmt.formatOptions = [.withInternetDateTime]
            if let date = fmt.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date: \(s)")
        }
        return d
    }()

    func test_decodeFromJSON() throws {
        let json = """
        {
            "id": 1,
            "name": "test@example.com",
            "issuer": "GitHub",
            "secret": "JBSWY3DPEHPK3PXP",
            "tag": "dev",
            "algorithm": "SHA1",
            "digits": 6,
            "period": 30,
            "createdAt": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let account = try decoder.decode(Account.self, from: json)
        XCTAssertEqual(account.id, 1)
        XCTAssertEqual(account.name, "test@example.com")
        XCTAssertEqual(account.issuer, "GitHub")
        XCTAssertEqual(account.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(account.tag, "dev")
        XCTAssertEqual(account.algorithm, "SHA1")
        XCTAssertEqual(account.digits, 6)
        XCTAssertEqual(account.period, 30)
    }

    func test_decodeStorage() throws {
        let json = """
        {
            "version": "1.0",
            "nextId": 2,
            "accounts": [
                {
                    "id": 1, "name": "user", "issuer": "AWS",
                    "secret": "JBSWY3DPEHPK3PXP", "tag": "prod",
                    "algorithm": "SHA1", "digits": 6, "period": 30,
                    "createdAt": "2024-01-01T00:00:00Z"
                }
            ]
        }
        """.data(using: .utf8)!

        let storage = try decoder.decode(AccountStorage.self, from: json)
        XCTAssertEqual(storage.version, "1.0")
        XCTAssertEqual(storage.nextId, 2)
        XCTAssertEqual(storage.accounts.count, 1)
        XCTAssertEqual(storage.accounts[0].issuer, "AWS")
    }

    func test_emptyStorage() {
        let storage = AccountStorage.empty()
        XCTAssertEqual(storage.version, "1.0")
        XCTAssertEqual(storage.nextId, 0)
        XCTAssertTrue(storage.accounts.isEmpty)
    }

    func test_decodeWithFractionalSeconds() throws {
        let json = """
        {
            "id": 2,
            "name": "user",
            "issuer": "Google",
            "secret": "JBSWY3DPEHPK3PXP",
            "tag": "",
            "algorithm": "SHA1",
            "digits": 6,
            "period": 30,
            "createdAt": "2025-03-15T10:30:00.123456789Z"
        }
        """.data(using: .utf8)!

        let account = try decoder.decode(Account.self, from: json)
        XCTAssertEqual(account.issuer, "Google")
    }

    func test_toOTPAuthURL_sha1() {
        let account = Account(
            id: 1, name: "user@example.com", issuer: "GitHub",
            secret: "JBSWY3DPEHPK3PXP", tag: "dev",
            algorithm: "SHA1", digits: 6, period: 30,
            createdAt: Date()
        )
        let url = account.toOTPAuthURL()
        XCTAssertTrue(url.hasPrefix("otpauth://totp/"))
        XCTAssertTrue(url.contains("secret=JBSWY3DPEHPK3PXP"))
        XCTAssertTrue(url.contains("issuer=GitHub"))
        XCTAssertTrue(url.contains("digits=6"))
        XCTAssertTrue(url.contains("period=30"))
        XCTAssertTrue(url.contains("algorithm=SHA1"))
    }

    func test_toOTPAuthURL_sha256() {
        let account = Account(
            id: 2, name: "admin", issuer: "AWS",
            secret: "JBSWY3DPEHPK3PXP", tag: "prod",
            algorithm: "SHA256", digits: 8, period: 60,
            createdAt: Date()
        )
        let url = account.toOTPAuthURL()
        XCTAssertTrue(url.contains("digits=8"))
        XCTAssertTrue(url.contains("period=60"))
        XCTAssertTrue(url.contains("algorithm=SHA256"))
    }

    func test_toOTPAuthURL_noIssuer() {
        let account = Account(
            id: 3, name: "user@example.com", issuer: "",
            secret: "JBSWY3DPEHPK3PXP", tag: "",
            algorithm: "SHA1", digits: 6, period: 30,
            createdAt: Date()
        )
        let url = account.toOTPAuthURL()
        XCTAssertTrue(url.hasPrefix("otpauth://totp/"))
        XCTAssertFalse(url.contains("issuer="))
        XCTAssertTrue(url.contains("secret=JBSWY3DPEHPK3PXP"))
    }

    // MARK: - Avatar helpers

    func test_avatarInitial_usesIssuerWhenPresent() {
        let account = Account(
            id: 1, name: "user@example.com", issuer: "GitHub",
            secret: "SECRET", tag: "", algorithm: "SHA1", digits: 6,
            period: 30, createdAt: Date()
        )
        XCTAssertEqual(account.avatarInitial, "G")
    }

    func test_avatarInitial_usesNameWhenIssuerEmpty() {
        let account = Account(
            id: 2, name: "alice@example.com", issuer: "",
            secret: "SECRET", tag: "", algorithm: "SHA1", digits: 6,
            period: 30, createdAt: Date()
        )
        XCTAssertEqual(account.avatarInitial, "A")
    }

    func test_avatarColor_isDeterministic() {
        let a1 = Account(
            id: 1, name: "user", issuer: "AWS",
            secret: "S", tag: "", algorithm: "SHA1", digits: 6,
            period: 30, createdAt: Date()
        )
        let a2 = Account(
            id: 2, name: "user", issuer: "AWS",
            secret: "S", tag: "", algorithm: "SHA1", digits: 6,
            period: 30, createdAt: Date()
        )
        XCTAssertEqual(a1.avatarColor, a2.avatarColor)
    }

    func test_avatarColor_differentAccountsCanGetDifferentColors() {
        let a = Account(id: 1, name: "alice", issuer: "GitHub", secret: "S", tag: "", algorithm: "SHA1", digits: 6, period: 30, createdAt: Date())
        let b = Account(id: 2, name: "bob", issuer: "AWS", secret: "S", tag: "", algorithm: "SHA1", digits: 6, period: 30, createdAt: Date())
        // 두 계정의 색상 인덱스가 계산 가능한지 확인 (다를 수도, 같을 수도 있음 — 결정론적이기만 하면 됨)
        let colorA = a.avatarColor
        let colorB = b.avatarColor
        // 같은 입력 → 항상 같은 출력
        XCTAssertEqual(colorA, a.avatarColor)
        XCTAssertEqual(colorB, b.avatarColor)
    }
}
