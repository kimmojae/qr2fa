import XCTest
@testable import qr2fa

final class MenuBarListTests: XCTestCase {

    private func account(_ id: Int, _ issuer: String, _ name: String, period: Int = 30) -> Account {
        Account(id: id, name: name, issuer: issuer, secret: "JBSWY3DPEHPK3PXP", tag: "",
                algorithm: "SHA1", digits: 6, period: period, createdAt: Date(timeIntervalSince1970: 0))
    }

    /// 계정이 하나뿐이어도 그룹이다 — 줄마다 생김새가 달라지지 않게.
    func test_issuerWithOneAccount_isStillAGroup() {
        let only = account(1, "GenAIR", "hjkim11")

        XCTAssertEqual(MenuBarList.groups(for: [only]),
                       [MenuBarGroup(issuer: "GenAIR", accounts: [only])])
    }

    func test_issuerWithTwoAccounts_becomesOneGroup() {
        let accounts = [account(1, "GitHub", "kimmojae"), account(2, "GitHub", "actions-bot")]

        XCTAssertEqual(MenuBarList.groups(for: accounts),
                       [MenuBarGroup(issuer: "GitHub", accounts: accounts)])
    }

    func test_groupsFollowStoredOrder_notAlphabetical() {
        let accounts = [
            account(1, "Zeta", "one"),
            account(2, "Alpha", "two"),
            account(3, "Zeta", "three")
        ]

        XCTAssertEqual(MenuBarList.groups(for: accounts).map(\.issuer), ["Zeta", "Alpha"])
    }

    /// 한 issuer의 계정이 배열에서 떨어져 있어도 한 그룹으로 모인다 — 다른 서비스 계정을
    /// 사이에 두고 추가하면 실제로 이렇게 저장된다.
    func test_interleavedAccountsOfOneIssuer_collapseIntoOneGroup() {
        let accounts = [
            account(1, "GitHub", "kimmojae"),
            account(2, "Alpha", "two"),
            account(3, "GitHub", "actions-bot")
        ]

        XCTAssertEqual(MenuBarList.groups(for: accounts), [
            MenuBarGroup(issuer: "GitHub", accounts: [accounts[0], accounts[2]]),
            MenuBarGroup(issuer: "Alpha", accounts: [accounts[1]])
        ])
    }

    /// issuer가 비면 계정 이름이 곧 서비스다(`displayIssuer`).
    func test_accountWithoutIssuer_isGroupedUnderItsName() {
        let bare = account(1, "", "standalone")

        XCTAssertEqual(MenuBarList.groups(for: [bare]),
                       [MenuBarGroup(issuer: "standalone", accounts: [bare])])
    }

    func test_emptyAccounts_produceNoGroups() {
        XCTAssertTrue(MenuBarList.groups(for: []).isEmpty)
    }

    // MARK: - commonPeriod

    func test_commonPeriod_whenAllAccountsAgree() {
        let accounts = [account(1, "A", "a"), account(2, "B", "b")]

        XCTAssertEqual(MenuBarList.commonPeriod(in: accounts), 30)
    }

    func test_commonPeriod_isNilWhenPeriodsDiffer() {
        let accounts = [account(1, "A", "a", period: 30), account(2, "B", "b", period: 60)]

        XCTAssertNil(MenuBarList.commonPeriod(in: accounts))
    }

    func test_commonPeriod_isNilWithNoAccounts() {
        XCTAssertNil(MenuBarList.commonPeriod(in: []))
    }
}
