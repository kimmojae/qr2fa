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

        XCTAssertEqual(AddedAccountFocus.issuer(for: added), "GitHub")
    }

    /// A Google export of one service should still land on that service's tab.
    func test_severalAccountsOfOneServiceFocusThatService() {
        let added = [
            account(id: 1, issuer: "AWS SSO", name: "a@example.com"),
            account(id: 2, issuer: "AWS SSO", name: "b@example.com"),
        ]

        XCTAssertEqual(AddedAccountFocus.issuer(for: added), "AWS SSO")
    }

    /// A mixed import has no single tab that shows everything — stay on 모든 계정.
    func test_mixedServicesFallBackToAllAccounts() {
        let added = [
            account(id: 1, issuer: "AWS SSO", name: "a@example.com"),
            account(id: 2, issuer: "GitHub", name: "b@example.com"),
        ]

        XCTAssertEqual(AddedAccountFocus.issuer(for: added), SettingsSelection.allAccounts)
    }

    /// The sidebar groups issuer-less accounts under their name, so focus must agree.
    func test_accountWithoutIssuerFocusesItsName() {
        let added = [account(id: 1, issuer: "", name: "solo@example.com")]

        XCTAssertEqual(AddedAccountFocus.issuer(for: added), "solo@example.com")
    }

    func test_nothingAddedChangesNothing() {
        XCTAssertNil(AddedAccountFocus.issuer(for: []))
    }
}
