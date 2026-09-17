import SwiftUI
import XCTest
@testable import qr2fa

final class TagStyleTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TagStyleTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_defaultsToTeal() {
        XCTAssertEqual(TagStyle(defaults: defaults).token, .teal)
    }

    func test_choiceSurvivesANewInstance() {
        TagStyle(defaults: defaults).token = .purple

        XCTAssertEqual(TagStyle(defaults: defaults).token, .purple)
    }

    /// 손으로 고쳤거나 예전 버전이 쓰던 이름이 남아 있을 수 있다. 그때 색이 없어서 태그가
    /// 안 보이는 것보다 기본값으로 떨어지는 편이 낫다.
    func test_unknownSavedNameFallsBackToTheDefault() {
        defaults.set("무지개", forKey: TagStyle.defaultsKey)

        XCTAssertEqual(TagStyle(defaults: defaults).token, .teal)
    }

    /// 파랑은 목록 선택 하이라이트와 같은 색이라, 선택된 행의 태그가 배경에 묻힌다.
    func test_blueIsNotOffered() {
        XCTAssertFalse(TagColorToken.allCases.contains { $0.rawValue == "blue" })
    }

    func test_everyTokenHasALabel() {
        for token in TagColorToken.allCases {
            XCTAssertFalse(token.label.isEmpty, "\(token.rawValue)에 이름이 없다")
        }
    }
}
