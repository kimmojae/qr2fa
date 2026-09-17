import AppKit
import Foundation
import Observation

/// 이 앱이 어디에 보이는지 — Dock과 메뉴바.
///
/// 기본은 둘 다 보인다. 일반 앱이면서 메뉴바에서 코드를 빠르게 복사하는 게 이 앱의 모양이다.
/// 둘 중 하나는 끌 수 있다: Dock을 끄면 메뉴바 유틸리티가 되고, 메뉴바를 끄면 평범한 앱이 된다.
///
/// **둘 다 끌 수는 없다.** 그러면 앱을 다시 부를 손잡이가 화면에서 사라진다. 실행 중인 앱을
/// Spotlight로 다시 여는 길이 남아 있긴 하지만, 그건 사용자가 알고 있으리라 기대할 수 있는
/// 지식이 아니다. 이 규칙은 **여기서** 지킨다 — 마지막 하나를 끄려는 대입은 조용히 되돌린다.
/// 화면의 비활성 표시는 안내일 뿐이고, 안내는 한 프레임 늦게 도착할 수 있다.
///
/// 두 값 다 "표시"로 둔다. 하나는 숨기기, 하나는 표시로 두면 같은 성격의 설정 둘이 반대로
/// 움직여서 볼 때마다 머리를 뒤집어야 한다. 저장은 반대로(`hides…`) 하는데, 그래야 값이
/// 없을 때(`bool(forKey:)`가 false) 자연스럽게 "보임"이 된다.
///
/// 활성화 정책을 정하는 곳도 여기 하나뿐이다. 예전에는 창을 열 때 `.regular`, 닫을 때
/// `.accessory`로 오갔는데, 그 전환 직후의 `activate`가 자주 무시돼서 "첫 클릭에 창이 안
/// 열린다", "창을 닫아도 Dock 아이콘이 남는다" 같은 증상이 계속 나왔다.
@Observable
final class AppPresence {
    static let dockKey = "hidesDockIcon"
    static let menuBarKey = "hidesMenuBarIcon"

    @ObservationIgnored private let defaults: UserDefaults

    var showsDockIcon: Bool {
        didSet {
            guard showsDockIcon || showsMenuBarIcon else {
                showsDockIcon = true
                return
            }
            defaults.set(!showsDockIcon, forKey: Self.dockKey)
            apply()
        }
    }

    /// `MenuBarExtra(isInserted:)`가 이 값을 그대로 본다.
    var showsMenuBarIcon: Bool {
        didSet {
            guard showsDockIcon || showsMenuBarIcon else {
                showsMenuBarIcon = true
                return
            }
            defaults.set(!showsMenuBarIcon, forKey: Self.menuBarKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let showsDock = !defaults.bool(forKey: Self.dockKey)
        let showsMenuBar = !defaults.bool(forKey: Self.menuBarKey)
        self.showsDockIcon = showsDock
        // 저장된 값이 둘 다 숨김이면(손으로 고쳤거나 예전 버전) 메뉴바를 되살린다.
        // 아무 데도 없는 앱으로 시작하는 것보다 낫다.
        self.showsMenuBarIcon = showsDock ? showsMenuBar : true
    }

    /// 지금 설정을 실제 활성화 정책에 반영한다. 실행 직후에 한 번, 그리고 값이 바뀔 때마다.
    func apply() {
        NSApp.setActivationPolicy(policy)
    }

    var policy: NSApplication.ActivationPolicy { showsDockIcon ? .regular : .accessory }

    /// 지금 켜져 있는 마지막 하나인지. 이 토글은 끌 수 없다.
    var dockIconIsTheLastOne: Bool { showsDockIcon && !showsMenuBarIcon }
    var menuBarIconIsTheLastOne: Bool { showsMenuBarIcon && !showsDockIcon }
}
