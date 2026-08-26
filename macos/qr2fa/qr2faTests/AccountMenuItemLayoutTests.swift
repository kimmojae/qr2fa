import AppKit
import XCTest
@testable import qr2fa

/// 메뉴바 서브메뉴 한 줄의 가로 배치 규칙.
/// 태그가 길어져도 배지 밖으로 새거나 이름과 겹치지 않아야 한다.
final class AccountMenuItemLayoutTests: XCTestCase {

    func test_badgeWidth_shortTagKeepsMinimumWidth() {
        let narrow = AccountMenuItemLayout.textWidth(for: "dev")
        XCTAssertLessThan(narrow + AccountMenuItemLayout.tagHPad * 2, AccountMenuItemLayout.tagMinW)
        XCTAssertEqual(AccountMenuItemLayout.badgeWidth(for: "dev"), AccountMenuItemLayout.tagMinW)
    }

    func test_badgeWidth_growsToFitLongTag() {
        let tag = "pantos-dev"
        let text = AccountMenuItemLayout.textWidth(for: tag)
        XCTAssertGreaterThan(text, AccountMenuItemLayout.tagMinW, "이 테스트가 의미 있으려면 최소 폭보다 넓은 태그여야 한다")
        XCTAssertGreaterThanOrEqual(
            AccountMenuItemLayout.badgeWidth(for: tag), text + AccountMenuItemLayout.tagHPad * 2
        )
    }

    func test_badgeWidth_clampedSoItCannotEatTheNameColumn() {
        let absurd = String(repeating: "장", count: 40)
        XCTAssertEqual(AccountMenuItemLayout.badgeWidth(for: absurd), AccountMenuItemLayout.tagMaxW)
    }

    func test_nameX_startsAfterTheBadge() {
        let badge = AccountMenuItemLayout.badgeWidth(for: "pantos-dev")
        XCTAssertEqual(
            AccountMenuItemLayout.nameX(badgeWidth: badge),
            AccountMenuItemLayout.lPad + badge + AccountMenuItemLayout.tagGap
        )
        XCTAssertEqual(AccountMenuItemLayout.nameX(badgeWidth: nil), AccountMenuItemLayout.lPad)
    }

    func test_tagColor_isTheSameSingleColorAsSettingsRegardlessOfTag() {
        let account = { (tag: String) in
            Account(id: 1, name: "n", issuer: "i", secret: "JBSWY3DPEHPK3PXP", tag: tag,
                    algorithm: "SHA1", digits: 6, period: 30, createdAt: Date(timeIntervalSince1970: 0))
        }
        for tag in ["dev", "prod", "rnd", "all", "pantos-dev"] {
            XCTAssertEqual(AccountMenuItemView(account: account(tag)).tagNSColor, TagPalette.nsColor,
                           "메뉴바 태그 색이 설정 창과 달라졌다 (태그: \(tag))")
        }
        XCTAssertEqual(TagBadgeView(tag: "dev").color, TagPalette.color)
    }

    func test_nameColumn_staysPositiveEvenWithWidestBadge() {
        let x = AccountMenuItemLayout.nameX(badgeWidth: AccountMenuItemLayout.tagMaxW)
        let codeX = AccountMenuItemLayout.itemW - AccountMenuItemLayout.rPad - AccountMenuItemLayout.codeW
        XCTAssertGreaterThan(codeX - x - 8, 0, "가장 넓은 배지에서도 이름 칼럼이 남아 있어야 한다")
    }
}
