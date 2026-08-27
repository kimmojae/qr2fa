import XCTest
@testable import qr2fa

final class DeleteConfirmationTests: XCTestCase {

    private func account(issuer: String, name: String, tag: String) -> Account {
        Account(
            id: 1, name: name, issuer: issuer, secret: "JBSWY3DPEHPK3PXP",
            tag: tag, algorithm: "SHA1", digits: 6, period: 30, createdAt: Date()
        )
    }

    /// Four "AWS SSO" accounts all produced the same title before — the name is what
    /// tells them apart, so the name is what goes in the title.
    func test_titleNamesTheAccount() {
        let acc = account(issuer: "AWS SSO", name: "hjkim11@bsgglobal.com-ktng", tag: "ktng")

        XCTAssertEqual(
            DeleteConfirmation.title(for: acc),
            "'hjkim11@bsgglobal.com-ktng' 계정을 삭제할까요?"
        )
    }

    func test_detailShowsServiceAndTag() {
        let acc = account(issuer: "AWS SSO", name: "a@example.com", tag: "ktng")

        XCTAssertTrue(DeleteConfirmation.detail(for: acc).hasPrefix("AWS SSO · 태그 ktng"))
    }

    func test_detailOmitsTagWhenThereIsNone() {
        let acc = account(issuer: "AWS SSO", name: "a@example.com", tag: "")

        XCTAssertTrue(DeleteConfirmation.detail(for: acc).hasPrefix("AWS SSO\n"))
    }

    func test_detailOmitsTheIdentityLineWhenThereIsNothingToAdd() {
        let acc = account(issuer: "", name: "solo@example.com", tag: "")

        XCTAssertFalse(DeleteConfirmation.detail(for: acc).contains("·"))
        XCTAssertTrue(DeleteConfirmation.detail(for: acc).hasPrefix("되돌릴 수 없습니다"))
    }

    /// The secret is unrecoverable — the warning has to say what that costs.
    func test_detailAlwaysWarnsThatTheSecretIsGone() {
        for acc in [
            account(issuer: "AWS SSO", name: "a@example.com", tag: "ktng"),
            account(issuer: "", name: "solo@example.com", tag: ""),
        ] {
            let detail = DeleteConfirmation.detail(for: acc)
            XCTAssertTrue(detail.contains("되돌릴 수 없습니다"))
            XCTAssertTrue(detail.contains("QR"))
        }
    }
}
