import AppKit
import XCTest
@testable import qr2fa

final class AppPresenceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppPresenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// 일반 앱이므로 아무 설정이 없으면 Dock에도, 메뉴바에도 뜬다.
    func test_bothAreVisibleByDefault() {
        let presence = AppPresence(defaults: defaults)

        XCTAssertTrue(presence.showsDockIcon)
        XCTAssertTrue(presence.showsMenuBarIcon)
        XCTAssertEqual(presence.policy, .regular)
    }

    func test_hidingTheDockIconMeansAccessory() {
        let presence = AppPresence(defaults: defaults)

        presence.showsDockIcon = false

        XCTAssertEqual(presence.policy, .accessory)
    }

    func test_choicesSurviveANewInstance() {
        AppPresence(defaults: defaults).showsMenuBarIcon = false

        XCTAssertFalse(AppPresence(defaults: defaults).showsMenuBarIcon)
    }

    /// 화면의 비활성 표시는 한 프레임 늦게 도착할 수 있다. 규칙은 값을 쥔 쪽이 지킨다 —
    /// 마지막 하나를 끄려는 대입은 조용히 되돌아온다.
    func test_turningOffTheLastOneIsRefused() {
        let presence = AppPresence(defaults: defaults)

        presence.showsMenuBarIcon = false
        presence.showsDockIcon = false

        XCTAssertTrue(presence.showsDockIcon, "둘 다 꺼지면 앱을 부를 손잡이가 없다")
        XCTAssertFalse(presence.showsMenuBarIcon)
    }

    func test_turningOffTheLastOneIsRefusedInTheOtherOrderToo() {
        let presence = AppPresence(defaults: defaults)

        presence.showsDockIcon = false
        presence.showsMenuBarIcon = false

        XCTAssertTrue(presence.showsMenuBarIcon)
        XCTAssertFalse(presence.showsDockIcon)
    }

    func test_refusalIsNotWrittenToDisk() {
        let presence = AppPresence(defaults: defaults)
        presence.showsMenuBarIcon = false
        presence.showsDockIcon = false

        XCTAssertTrue(AppPresence(defaults: defaults).showsDockIcon)
    }

    func test_knowsWhichToggleIsTheLastOne() {
        let presence = AppPresence(defaults: defaults)
        XCTAssertFalse(presence.dockIconIsTheLastOne)
        XCTAssertFalse(presence.menuBarIconIsTheLastOne)

        presence.showsMenuBarIcon = false
        XCTAssertTrue(presence.dockIconIsTheLastOne)
        XCTAssertFalse(presence.menuBarIconIsTheLastOne)
    }

    /// 저장된 값이 둘 다 숨김이면(손으로 고쳤거나 예전 버전) 메뉴바를 되살린다.
    func test_aStateWithNoHandleAtAllRecovers() {
        defaults.set(true, forKey: AppPresence.dockKey)
        defaults.set(true, forKey: AppPresence.menuBarKey)

        XCTAssertTrue(AppPresence(defaults: defaults).showsMenuBarIcon)
    }
}
