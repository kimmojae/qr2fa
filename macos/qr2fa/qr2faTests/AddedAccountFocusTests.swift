import XCTest
@testable import qr2fa

final class AddedAccountFocusTests: XCTestCase {

    private func account(id: Int, issuer: String, name: String) -> Account {
        Account(
            id: id, name: name, issuer: issuer, secret: "JBSWY3DPEHPK3PXP",
            tag: "", algorithm: "SHA1", digits: 6, period: 30, createdAt: Date()
        )
    }

    func test_singleAccountFocusesItsService() {
        let added = [account(id: 1, issuer: "GitHub", name: "me@example.com")]

        XCTAssertEqual(AddedAccountFocus.destination(for: added), .issuer("GitHub"))
    }

    /// A Google export of one service should still land on that service's tab.
    func test_severalAccountsOfOneServiceFocusThatService() {
        let added = [
            account(id: 1, issuer: "AWS SSO", name: "a@example.com"),
            account(id: 2, issuer: "AWS SSO", name: "b@example.com"),
        ]

        XCTAssertEqual(AddedAccountFocus.destination(for: added), .issuer("AWS SSO"))
    }

    /// A mixed import has no single tab that shows everything — stay on 모든 계정.
    func test_mixedServicesFallBackToAllAccounts() {
        let added = [
            account(id: 1, issuer: "AWS SSO", name: "a@example.com"),
            account(id: 2, issuer: "GitHub", name: "b@example.com"),
        ]

        XCTAssertEqual(AddedAccountFocus.destination(for: added), .allAccounts)
    }

    /// The sidebar groups issuer-less accounts under their name, so focus must agree.
    func test_accountWithoutIssuerFocusesItsName() {
        let added = [account(id: 1, issuer: "", name: "solo@example.com")]

        XCTAssertEqual(AddedAccountFocus.destination(for: added), .issuer("solo@example.com"))
    }

    /// 서비스 이름이 우연히 예전 센티넬 문자열과 같아도 서비스로 다뤄진다 —
    /// 문자열 비교가 아니라 타입으로 구분하기 때문이다.
    func test_serviceNamedLikeAnOldSentinelIsStillAService() {
        let added = [account(id: 1, issuer: "__all__", name: "a@example.com")]

        XCTAssertEqual(AddedAccountFocus.destination(for: added), .issuer("__all__"))
    }

    func test_nothingAddedChangesNothing() {
        XCTAssertNil(AddedAccountFocus.destination(for: []))
    }
}
