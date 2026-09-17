import XCTest
@testable import qr2fa

final class TOTPClockTests: XCTestCase {

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    func test_nextTickIsTheFollowingWholeSecond() {
        XCTAssertEqual(TOTPClock.nextTick(after: date(10.4)), date(11))
        XCTAssertEqual(TOTPClock.nextTick(after: date(10.999)), date(11))
    }

    /// 정각에 물으면 "지금"이 아니라 다음 초를 줘야 한다. 지금을 주면 타이머가 0초 뒤에
    /// 깨어나 같은 값을 또 쓴다.
    func test_nextTickFromAWholeSecondIsTheNextOne() {
        XCTAssertEqual(TOTPClock.nextTick(after: date(10)), date(11))
    }

    /// 두 화면이 같은 시계를 보면 같은 초를 본다 — 위상이 하나뿐이기 때문이다.
    func test_ticksLandOnSecondBoundaries() {
        let tick = TOTPClock.nextTick(after: date(10.4))
        XCTAssertEqual(tick.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1), 0)
    }
}
