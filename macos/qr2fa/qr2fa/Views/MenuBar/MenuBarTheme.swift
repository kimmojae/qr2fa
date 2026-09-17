import SwiftUI

/// 메뉴바 패널에서 라이트/다크 값이 다른 색.
///
/// 나머지는 전부 `.primary` / `.secondary` / `.tertiary` 와 `MenuBarExtra` 팝오버의 시스템
/// 머티리얼에 맡긴다 — 패널 배경을 직접 칠하면 메뉴바 팝오버 특유의 반투명이 사라진다.
extension Color {
    /// 호버 중인 행의 코드. 검정 위에서는 밝기를 올리고 채도를 낮춘 값을 쓴다 —
    /// `#0A6CFF`는 어두운 배경에서 탁해진다.
    static let codeAccent = menuBarDynamic(light: 0x0A6CFF, dark: 0x5EA9FF)

    /// 코드 만료가 임박했을 때의 남은 시간. 코드 자체가 아니라 타이머에만 쓴다 —
    /// 코드 색은 이미 호버와 복사 완료 두 가지 뜻을 쓰고 있다.
    ///
    /// 설정 창의 `CountdownRing`도 같은 값을 쓴다. 메뉴바와 설정에서 "곧 만료"가
    /// 다른 색이면 같은 뜻인 줄 모른다.
    static let codeExpiring = menuBarDynamic(light: 0xB26A00, dark: 0xE8A33D)

    /// 복사 완료 표시. 시스템 초록보다 살짝 가라앉혀 패널의 조용한 톤을 유지한다.
    static let codeCopied = menuBarDynamic(light: 0x1A7F45, dark: 0x3FD97F)

    private static func menuBarDynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(menuBarHex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(menuBarHex hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
