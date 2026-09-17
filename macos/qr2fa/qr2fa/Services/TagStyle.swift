import Foundation
import Observation
import SwiftUI

/// 태그에 쓰는 대표 색 하나. 태그마다 다른 색을 주지는 않는다 — 태그는 이름으로 읽는
/// 것이고, 색이 여럿이면 의미 없는 규칙을 외우게 만든다. 대신 그 **하나를 고를 수** 있다.
///
/// 고를 수 있는 건 시스템 색 여덟 개뿐이다. `ColorPicker`로 아무 값이나 받으면 라이트/다크
/// 중 한쪽에서 안 보이는 색을 고를 수 있는데, 태그는 글자색으로 쓰이므로 그건 곧 안 읽히는
/// 태그다. 시스템 색은 두 모드에서 각각 다른 실제 값으로 그려진다.
///
/// 파랑은 넣지 않았다. 목록에서 선택된 행의 하이라이트와 같은 색이라, 선택된 계정의 태그가
/// 배경에 묻힌다.
enum TagColorToken: String, CaseIterable, Identifiable {
    case teal, mint, green, yellow, orange, red, pink, purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .teal: .teal
        case .mint: .mint
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        }
    }

    var label: String {
        switch self {
        case .teal: "청록"
        case .mint: "민트"
        case .green: "초록"
        case .yellow: "노랑"
        case .orange: "주황"
        case .red: "빨강"
        case .pink: "분홍"
        case .purple: "보라"
        }
    }
}

/// 고른 태그 색. 설정 창과 메뉴바가 **같은 객체**를 봐야 한 곳에서 바꾼 게 다른 곳에
/// 바로 반영된다.
///
/// 색 이름(`"teal"`)을 저장하지 RGB 값을 저장하지 않는다. 값으로 굳혀 두면 다크 모드
/// 대응이 그 순간의 값에 묶이는데, 이름으로 두면 그리는 일은 계속 시스템이 한다.
///
/// `accounts.json`이 아니라 `UserDefaults`에 둔다 — 계정 데이터가 아니라 이 Mac의 취향이고,
/// CLI와 주고받는 파일 형식을 UI 설정으로 건드릴 이유가 없다.
@Observable
final class TagStyle {
    static let defaultsKey = "tagColor"
    static let fallback = TagColorToken.teal

    @ObservationIgnored private let defaults: UserDefaults

    var token: TagColorToken {
        didSet { defaults.set(token.rawValue, forKey: Self.defaultsKey) }
    }

    /// 저장된 이름을 못 알아보면 기본값으로 떨어진다. 손으로 고쳤거나, 예전 버전이 쓰던
    /// 이름이 남아 있을 수 있다 — 그때 색이 없어서 태그가 안 보이는 것보다는 낫다.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.defaultsKey)
        self.token = saved.flatMap(TagColorToken.init(rawValue:)) ?? Self.fallback
    }

    var color: Color { token.color }
}
