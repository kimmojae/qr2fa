import XCTest
@testable import qr2fa

final class MenuBarExpansionTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MenuBarExpansionTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_nothingIsExpandedOnFirstRun() {
        XCTAssertFalse(MenuBarExpansion(defaults: defaults).isExpanded("GitHub"))
    }

    func test_toggleExpandsThenCollapses() {
        let expansion = MenuBarExpansion(defaults: defaults)

        expansion.toggle("GitHub")
        XCTAssertTrue(expansion.isExpanded("GitHub"))

        expansion.toggle("GitHub")
        XCTAssertFalse(expansion.isExpanded("GitHub"))
    }

    func test_expansionSurvivesANewInstance() {
        MenuBarExpansion(defaults: defaults).toggle("AWS SSO")

        XCTAssertTrue(MenuBarExpansion(defaults: defaults).isExpanded("AWS SSO"))
    }

    /// 아코디언 — 다른 issuer를 열면 이전 것이 접힌다. 패널 높이를 묶기 위한 규칙이다.
    func test_openingAnotherIssuerCollapsesThePreviousOne() {
        let expansion = MenuBarExpansion(defaults: defaults)

        expansion.toggle("GitHub")
        expansion.toggle("AWS SSO")

        XCTAssertFalse(expansion.isExpanded("GitHub"))
        XCTAssertTrue(expansion.isExpanded("AWS SSO"))
    }

    func test_collapsingSurvivesANewInstance() {
        let first = MenuBarExpansion(defaults: defaults)
        first.toggle("GitHub")
        first.toggle("GitHub")

        XCTAssertNil(MenuBarExpansion(defaults: defaults).expanded)
    }

    func test_pruneForgetsAnIssuerThatNoLongerExists() {
        let expansion = MenuBarExpansion(defaults: defaults)
        expansion.toggle("Gone")

        expansion.prune(keeping: ["GitHub"])

        XCTAssertNil(expansion.expanded)
        XCTAssertNil(MenuBarExpansion(defaults: defaults).expanded)
    }

    func test_pruneKeepsAnIssuerThatStillExists() {
        let expansion = MenuBarExpansion(defaults: defaults)
        expansion.toggle("GitHub")

        expansion.prune(keeping: ["AWS SSO", "GitHub"])

        XCTAssertTrue(expansion.isExpanded("GitHub"))
    }

    /// 계정이 0개로 보이는 순간(아직 안 읽힘, 금고 잠김)에 패널이 열리면 prune이 돈다.
    /// 그때 지워 버리면 펼쳐 둔 issuer가 패널 한 번 여는 것으로 날아간다.
    func test_pruneWithNothingAlive_keepsExpansion() {
        let expansion = MenuBarExpansion(defaults: defaults)
        expansion.toggle("GitHub")

        expansion.prune(keeping: [])

        XCTAssertTrue(expansion.isExpanded("GitHub"))
        XCTAssertTrue(MenuBarExpansion(defaults: defaults).isExpanded("GitHub"))
    }
}
