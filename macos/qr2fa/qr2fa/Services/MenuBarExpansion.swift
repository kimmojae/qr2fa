import Foundation
import Observation

/// 메뉴바 패널에서 펼쳐 둔 issuer. 패널을 닫았다 열어도, 앱을 껐다 켜도 유지된다.
///
/// **한 번에 하나만 펼쳐진다.** 다른 issuer를 열면 이전 것은 접힌다 — 그래야 패널 높이가
/// 목록 길이와 무관하게 묶인다(issuer 7개를 다 펼치면 650px, 하나면 350px 안쪽). 그 대신
/// issuer를 옮길 때마다 클릭이 한 번 든다.
///
/// 펼침은 **클릭으로만** 바뀐다. 호버로 펼치는 방식도 만들어 봤는데, 그룹이 펼쳐지면 아래
/// 그룹들이 밀려 내려가는 세로 목록이라 체류 시간에 좋은 값이 없었다 — 짧으면 지나가다
/// 열려서 목표가 도망가고, 길면 매번 기다린다. 클릭+유지는 자주 쓰는 issuer를 한 번
/// 열어두면 그다음부터 0클릭이라 어떤 체류 시간보다도 빠르다.
///
/// 기기마다 다른 습관이므로 `accounts.json`이 아니라 `UserDefaults`에 둔다(CLI와 무관).
@Observable
final class MenuBarExpansion {
    static let defaultsKey = "expandedIssuer"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var expanded: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.expanded = defaults.string(forKey: Self.defaultsKey)
    }

    func isExpanded(_ issuer: String) -> Bool { expanded == issuer }

    func toggle(_ issuer: String) {
        expanded = (expanded == issuer) ? nil : issuer
        save()
    }

    /// 펼쳐 둔 issuer가 목록에서 사라졌으면 잊는다. 이름을 바꾸거나 마지막 계정을 지우면
    /// 그 issuer는 없어지는데, 남겨 두면 나중에 같은 이름이 다시 생겼을 때 영문 모르게
    /// 펼쳐진 채로 나타난다.
    ///
    /// **비어 있으면 아무것도 지우지 않는다.** 계정이 0개인 상태는 "정말 다 지웠다"와
    /// "아직 안 읽혔다 / 금고가 잠겼다"를 구별할 수 없는데, 후자에서 지워 버리면 패널을
    /// 한 번 여는 것만으로 펼쳐 둔 issuer가 날아간다. 실제로 그렇게 날아갔다.
    func prune(keeping issuers: some Sequence<String>) {
        guard let current = expanded else { return }
        var sawAny = false
        for issuer in issuers {
            sawAny = true
            if issuer == current { return }
        }
        guard sawAny else { return }
        expanded = nil
        save()
    }

    private func save() {
        if let expanded {
            defaults.set(expanded, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }
}
