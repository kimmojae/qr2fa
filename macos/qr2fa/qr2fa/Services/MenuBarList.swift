import Foundation

/// 메뉴바 패널의 issuer 한 덩어리.
///
/// 계정이 하나뿐인 issuer도 그룹으로 둔다 — 줄마다 생김새가 달라지는 것보다, 모든 줄이
/// 같은 규칙(접힌 issuer 하나)을 따르는 쪽이 읽기 쉽다.
struct MenuBarGroup: Identifiable, Equatable {
    let issuer: String
    let accounts: [Account]

    var id: String { issuer }
}

enum MenuBarList {

    /// 저장된 순서(= `accounts.json` 배열 순서)를 그대로 따른다. 설정 창에서 끌어 옮긴
    /// 순서가 메뉴바에도 그대로 보여야 한다.
    static func groups(for accounts: [Account]) -> [MenuBarGroup] {
        AccountOrdering.issuers(in: accounts).map { issuer in
            MenuBarGroup(issuer: issuer,
                         accounts: accounts.filter { $0.displayIssuer == issuer })
        }
    }

    /// 모든 계정이 같은 주기를 쓸 때 그 주기, 아니면 nil.
    ///
    /// 주기가 같으면 코드가 전부 같은 순간에 갱신되므로 남은 시간을 헤더에 하나만 두면
    /// 된다. 섞여 있으면 헤더의 숫자가 일부 계정에 대해 거짓말이 되므로, 그때는 헤더에서
    /// 빼고 행마다 각자의 남은 시간을 보여준다.
    static func commonPeriod(in accounts: [Account]) -> Int? {
        guard let first = accounts.first?.period else { return nil }
        return accounts.allSatisfy { $0.period == first } ? first : nil
    }
}
