import XCTest
@testable import qr2fa

final class AccountOrderingTests: XCTestCase {

    private func account(_ id: Int, _ issuer: String, name: String = "") -> Account {
        Account(
            id: id, name: name.isEmpty ? "user\(id)@example.com" : name,
            issuer: issuer, secret: "JBSWY3DPEHPK3PXP", tag: "",
            algorithm: "SHA1", digits: 6, period: 30, createdAt: Date()
        )
    }

    private func issuers(_ accounts: [Account]) -> [String] {
        AccountOrdering.issuers(in: accounts)
    }

    // MARK: - issuers(in:)

    /// Alphabetical order was forced before; the stored order is what counts now.
    func test_issuersFollowFirstAppearance() {
        let accounts = [account(1, "Zulu"), account(2, "Alpha"), account(3, "Mike")]

        XCTAssertEqual(issuers(accounts), ["Zulu", "Alpha", "Mike"])
    }

    func test_issuersAreDeduped() {
        let accounts = [account(1, "AWS SSO"), account(2, "GitHub"), account(3, "AWS SSO")]

        XCTAssertEqual(issuers(accounts), ["AWS SSO", "GitHub"])
    }

    /// The sidebar groups an issuer-less account under its name.
    func test_issuerlessAccountIsItsOwnService() {
        let accounts = [account(1, "", name: "solo@example.com")]

        XCTAssertEqual(issuers(accounts), ["solo@example.com"])
    }

    // MARK: - movingIssuers

    func test_movingAServiceToTheFront() {
        let accounts = [account(1, "A"), account(2, "B"), account(3, "C")]

        let moved = AccountOrdering.movingIssuers(in: accounts, from: IndexSet([2]), to: 0)

        XCTAssertEqual(issuers(moved), ["C", "A", "B"])
    }

    func test_movingAServiceToTheEnd() {
        let accounts = [account(1, "A"), account(2, "B"), account(3, "C")]

        let moved = AccountOrdering.movingIssuers(in: accounts, from: IndexSet([0]), to: 3)

        XCTAssertEqual(issuers(moved), ["B", "C", "A"])
    }

    func test_movingAServiceDownByOne() {
        let accounts = [account(1, "A"), account(2, "B"), account(3, "C")]

        let moved = AccountOrdering.movingIssuers(in: accounts, from: IndexSet([0]), to: 2)

        XCTAssertEqual(issuers(moved), ["B", "A", "C"])
    }

    /// A service moves as a block — its own accounts keep their relative order.
    func test_aServiceKeepsItsInternalOrder() {
        let accounts = [
            account(1, "AWS SSO"), account(2, "AWS SSO"), account(3, "AWS SSO"),
            account(4, "GitHub"),
        ]

        let moved = AccountOrdering.movingIssuers(in: accounts, from: IndexSet([1]), to: 0)

        XCTAssertEqual(moved.map(\.id), [4, 1, 2, 3])
    }

    /// Accounts added in mixed order are interleaved in the array; moving a service
    /// gathers every group into a block. Relative order of the others is untouched.
    func test_movingGathersInterleavedServicesIntoBlocks() {
        let accounts = [
            account(1, "A"), account(2, "B"), account(3, "A"), account(4, "B"),
        ]

        let moved = AccountOrdering.movingIssuers(in: accounts, from: IndexSet([1]), to: 0)

        XCTAssertEqual(issuers(moved), ["B", "A"])
        XCTAssertEqual(moved.map(\.id), [2, 4, 1, 3])
    }

    func test_movingNothingChangesNothing() {
        let accounts = [account(1, "A"), account(2, "B")]

        let moved = AccountOrdering.movingIssuers(in: accounts, from: IndexSet(), to: 1)

        XCTAssertEqual(moved.map(\.id), [1, 2])
    }

    /// Reordering must never lose or duplicate an account — the secrets are unrecoverable.
    func test_movingNeverLosesAnAccount() {
        let accounts = (1...6).map { account($0, ["A", "B", "C"][$0 % 3]) }

        for destination in 0...3 {
            let moved = AccountOrdering.movingIssuers(in: accounts, from: IndexSet([1]), to: destination)
            XCTAssertEqual(Set(moved.map(\.id)), Set(accounts.map(\.id)))
            XCTAssertEqual(moved.count, accounts.count)
        }
    }

    // MARK: - movingAccounts

    func test_movingAnAccountWithinItsService() {
        let accounts = [
            account(1, "AWS SSO"), account(2, "AWS SSO"), account(3, "AWS SSO"),
        ]

        let moved = AccountOrdering.movingAccounts(
            in: accounts, issuer: "AWS SSO", from: IndexSet([2]), to: 0
        )

        XCTAssertEqual(moved.map(\.id), [3, 1, 2])
    }

    /// Other services must not shift — only the dragged service's slots are rewritten.
    func test_movingAnAccountLeavesOtherServicesInPlace() {
        let accounts = [
            account(1, "AWS SSO"), account(2, "GitHub"),
            account(3, "AWS SSO"), account(4, "GitHub"),
        ]

        let moved = AccountOrdering.movingAccounts(
            in: accounts, issuer: "AWS SSO", from: IndexSet([1]), to: 0
        )

        // AWS SSO occupies slots 0 and 2; GitHub keeps slots 1 and 3.
        XCTAssertEqual(moved.map(\.id), [3, 2, 1, 4])
        XCTAssertEqual(issuers(moved), ["AWS SSO", "GitHub"])
    }

    func test_movingAnAccountToTheEnd() {
        let accounts = [account(1, "A"), account(2, "A"), account(3, "A")]

        let moved = AccountOrdering.movingAccounts(
            in: accounts, issuer: "A", from: IndexSet([0]), to: 3
        )

        XCTAssertEqual(moved.map(\.id), [2, 3, 1])
    }

    func test_movingAnAccountOfAnUnknownServiceChangesNothing() {
        let accounts = [account(1, "A"), account(2, "B")]

        let moved = AccountOrdering.movingAccounts(
            in: accounts, issuer: "Nope", from: IndexSet([0]), to: 1
        )

        XCTAssertEqual(moved.map(\.id), [1, 2])
    }

    func test_movingAnAccountNeverLosesAnAccount() {
        let accounts = (1...6).map { account($0, $0 <= 3 ? "A" : "B") }

        for destination in 0...3 {
            let moved = AccountOrdering.movingAccounts(
                in: accounts, issuer: "A", from: IndexSet([1]), to: destination
            )
            XCTAssertEqual(Set(moved.map(\.id)), Set(accounts.map(\.id)))
            XCTAssertEqual(moved.count, accounts.count)
        }
    }
}
