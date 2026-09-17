import XCTest
@testable import qr2fa

/// `memo`가 생기기 전에 저장된 파일이 그대로 읽히는지. 여기가 깨지면 기존 계정이 통째로
/// 사라진 것처럼 보이고, 담긴 시크릿은 복구할 수 없다.
final class AccountMemoCodingTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// memo 키가 아예 없는 예전 파일.
    private let legacyJSON = """
    {
      "id": 1,
      "name": "mojaekim@gmail.com",
      "issuer": "GitHub",
      "secret": "JBSWY3DPEHPK3PXP",
      "tag": "personal",
      "algorithm": "SHA1",
      "digits": 6,
      "period": 30,
      "createdAt": "2026-03-11T00:00:00Z"
    }
    """.data(using: .utf8)!

    func test_legacyAccountWithoutMemoStillDecodes() throws {
        let account = try decoder.decode(Account.self, from: legacyJSON)

        XCTAssertEqual(account.id, 1)
        XCTAssertEqual(account.issuer, "GitHub")
        XCTAssertEqual(account.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(account.memo, "", "빠진 키는 빈 메모로 채워져야 한다")
    }

    func test_memoSurvivesARoundTrip() throws {
        var account = try decoder.decode(Account.self, from: legacyJSON)
        account.memo = "회사 계정 — 팀 공용"

        let restored = try decoder.decode(Account.self, from: encoder.encode(account))

        XCTAssertEqual(restored.memo, "회사 계정 — 팀 공용")
    }

    /// 다른 필드가 빠진 건 여전히 실패해야 한다 — memo만 선택적이다.
    func test_missingRequiredFieldStillFails() {
        let broken = """
        {"id": 1, "name": "a", "issuer": "b", "tag": "", "algorithm": "SHA1",
         "digits": 6, "period": 30, "createdAt": "2026-03-11T00:00:00Z"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(Account.self, from: broken))
    }
}
