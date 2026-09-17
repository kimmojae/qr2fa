import Foundation
import Observation

/// 앱 전체가 공유하는 "지금". 1초에 한 번 갱신된다.
///
/// 화면마다 타이머를 돌리면 **같은 순간에 다른 초를 보여 준다.** 각자의 타이머가 시작된
/// 시점이 다르므로 초 경계를 넘는 타이밍이 제각각이고, 메뉴바 패널과 설정 창을 나란히
/// 띄우면 한쪽 링이 다 찼는데 다른 쪽은 아직 한 칸 남아 있다. 남은 초 자체는 절대 시각에서
/// 나오니 틀린 값은 아니지만, 화면에 같이 보이는 이상 같아야 한다.
///
/// **초 경계에 맞춰 뛴다.** `Timer.publish(every: 1)`은 시작한 순간의 위상을 그대로 물고
/// 가서 23.4초, 24.4초… 하는 식으로 뛴다. 코드가 실제로 바뀌는 건 정각이므로, 그 사이
/// 0.4초 동안은 링이 다 찼는데 코드는 아직 옛것인 상태가 보인다.
@Observable
final class TOTPClock {
    private(set) var now: Date

    @ObservationIgnored private var timer: Timer?

    init(now: Date = Date()) {
        self.now = now
        schedule()
    }

    deinit { timer?.invalidate() }

    /// `date` 다음에 오는 초 경계. 정각이면 그다음 초를 준다 — 지금 이 순간을 돌려주면
    /// 타이머가 0초 뒤에 깨어나 같은 값을 또 쓴다.
    static func nextTick(after date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: seconds.rounded(.down) + 1)
    }

    private func schedule() {
        let timer = Timer(fire: Self.nextTick(after: now), interval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        // `.common` 모드라야 메뉴를 열어 두거나 창을 끄는 동안에도 계속 뛴다.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
