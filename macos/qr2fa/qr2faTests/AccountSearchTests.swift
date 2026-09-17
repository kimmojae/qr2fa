import XCTest
@testable import qr2fa

final class AccountSearchTests: XCTestCase {

    private func account(_ id: Int, issuer: String, name: String, tag: String = "") -> Account {
        Account(id: id, name: name, issuer: issuer, secret: "JBSWY3DPEHPK3PXP", tag: tag,
                algorithm: "SHA1", digits: 6, period: 30, createdAt: Date(timeIntervalSince1970: 0))
    }

    private lazy var accounts = [
        account(1, issuer: "GitHub", name: "mojaekim@gmail.com"),
        account(2, issuer: "AWS SSO", name: "hjkim11@bsgglobal.com", tag: "prod"),
        account(3, issuer: "AWS SSO", name: "hjkim11@bsgglobal.com-sa", tag: "dev"),
        account(4, issuer: "", name: "standalone")
    ]

    func test_emptyQueryKeepsEverything() {
        XCTAssertEqual(AccountSearch.filter(accounts, query: "").map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(AccountSearch.filter(accounts, query: "   ").map(\.id), [1, 2, 3, 4])
    }

    func test_matchesIssuer() {
        XCTAssertEqual(AccountSearch.filter(accounts, query: "aws").map(\.id), [2, 3])
    }

    func test_matchesAccountName() {
        XCTAssertEqual(AccountSearch.filter(accounts, query: "mojaekim").map(\.id), [1])
    }

    func test_matchesTag() {
        XCTAssertEqual(AccountSearch.filter(accounts, query: "prod").map(\.id), [2])
    }

    func test_isCaseInsensitive() {
        XCTAssertEqual(AccountSearch.filter(accounts, query: "GiThUb").map(\.id), [1])
    }

    /// 낱말이 여럿이면 전부 걸려야 한다 — `aws prod`처럼 좁혀 들어가는 입력.
    func test_allTermsMustMatch() {
        XCTAssertEqual(AccountSearch.filter(accounts, query: "aws prod").map(\.id), [2])
        XCTAssertTrue(AccountSearch.filter(accounts, query: "aws github").isEmpty)
    }

    /// issuer가 비면 계정 이름이 곧 서비스다(`displayIssuer`) — 검색도 그걸 따라야 한다.
    func test_accountWithoutIssuerIsFoundByItsName() {
        XCTAssertEqual(AccountSearch.filter(accounts, query: "standalone").map(\.id), [4])
    }

    func test_noMatchReturnsEmpty() {
        XCTAssertTrue(AccountSearch.filter(accounts, query: "없는것").isEmpty)
    }
}
