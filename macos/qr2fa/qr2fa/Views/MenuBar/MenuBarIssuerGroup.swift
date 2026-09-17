import SwiftUI

/// issuer 하나. 접힌 한 줄로 있다가 제자리에서 펼쳐진다.
///
/// 펼침은 **클릭으로만** 바뀌고 그대로 유지된다. 호버로 펼치는 방식도 만들어 봤지만 이
/// 레이아웃과 맞지 않았다 — 이유는 `MenuBarExpansion` 주석에 적어 뒀다. 호버는 배경
/// 하이라이트에만 쓴다.
struct MenuBarIssuerGroup: View {
    let group: MenuBarGroup
    let showsOwnCountdown: Bool
    let now: Date
    let tagStyle: TagStyle
    let isExpanded: Bool
    let toggle: () -> Void

    /// 헤더 줄에만 포인터가 있는지. 그룹 전체를 쓰면 안쪽 계정 행에 호버할 때 헤더까지
    /// 같이 칠해져 두 블록이 붙어 보인다.
    @State private var isHeaderHovered = false

    var body: some View {
        VStack(spacing: 2) {
            header
            if isExpanded { rows }
        }
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isExpanded ? Color.primary.opacity(0.05) : .clear)
        )
    }

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { toggle() }
        } label: {
            HStack(spacing: 8) {
                // 아이콘은 두지 않는다. 모든 그룹에 같은 글리프가 반복되면 아무것도 구별해
                // 주지 못하면서 긴 issuer 이름의 폭만 가져간다. 그룹이라는 건 오른쪽 셰브런과
                // 계정 수가, 계정 행과의 차이는 행 왼쪽의 모노 코드가 이미 말해 준다.
                // issuer가 이 목록의 1차 탐색 키다. 접혀 있을 때는 목록 전체가 이 줄이므로
                // 계정 이름보다 작거나 흐리면 안 된다 — 굵기로 한 단계 위에 둔다.
                Text(group.issuer)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("· \(group.accounts.count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                chevron
            }
            .font(.caption)
            // 접혔다고 흐리게 두지 않는다. 아무것도 안 펼친 평소 상태에서 목록 전체가
            // 흐려 보이기 때문이다. 펼침 여부는 배경과 셰브런이 이미 말해 준다.
            .foregroundStyle(.primary)
            // 목록 전체가 6pt 안쪽에 있으므로 여기서 8을 더해 14를 만든다 — 패널 제목과
            // 푸터가 쓰는 값이고, 계정 행의 코드가 시작하는 자리이기도 하다. 세 줄이
            // 같은 세로선에서 시작해야 패널이 한 덩어리로 보인다.
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuBarRowButtonStyle(isHovered: isHeaderHovered))
        .accessibilityLabel("\(group.issuer), 계정 \(group.accounts.count)개")
        .accessibilityHint(isExpanded ? "접으려면 누르세요" : "펼치려면 누르세요")
        .onHover { isHeaderHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHeaderHovered)
    }

    /// 작은 크기에서 글리프를 바꾸면(원 안의 셰브런 같은 것) 뭉개지므로 방향만 바꾼다.
    private var chevron: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .frame(width: 12)
            .opacity(isExpanded ? 1 : (isHeaderHovered ? 0.7 : 0.35))
    }

    private var rows: some View {
        VStack(spacing: 1) {
            ForEach(group.accounts) { account in
                MenuBarAccountRow(account: account,
                                  showsOwnCountdown: showsOwnCountdown,
                                  now: now,
                                  tagStyle: tagStyle)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 5)
    }
}
