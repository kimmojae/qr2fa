import SwiftUI

/// 코드가 바뀌기까지 남은 시간을 그리는 링. 설정 창의 목록 툴바와 상세의 인증 코드 줄이
/// 같은 것을 쓴다 — 한 화면에 둘이 같이 보이므로 규칙이 갈리면 바로 티가 난다.
///
/// **차오른다.** 줄어드는 게 아니라 0에서 한 바퀴를 채우고, 주기가 끝나면 값이 되돌아가면서
/// 링도 거꾸로 풀린다. 1초짜리 선형 애니메이션이 그 되돌림까지 이어 그려 줘서 툭 끊기지 않는다.
///
/// **5초가 남으면 주황.** 암호 앱은 끝까지 한 가지 색으로 가는데, 여기서는 지금 복사하면
/// 붙여 넣기도 전에 만료될 수 있다는 걸 색으로 알린다. 되돌아간 뒤에는 다시 초록이다 —
/// 새 코드는 급하지 않으니까.
///
/// 색이 바뀌는 방식은 **주황 호를 초록 호 위에 겹쳐 두고 투명도만 여닫는** 것이다. 획의
/// 색을 통째로 갈아 끼우면 SwiftUI가 그 둘 사이를 실제로 섞어 줄지가 `ShapeStyle` 구현에
/// 달리는데, 투명도는 무조건 섞인다. 메뉴바 링(13pt·선 2)은 색이 칠해진 면적이 설정 창
/// 링(15pt·선 3)의 절반이 안 돼서, 섞이지 않으면 그쪽에서 먼저 티가 난다.
///
/// 호가 차는 것과 색이 바뀌는 건 속도가 다르다 — 채움은 1초 선형(다음 틱까지 정확히
/// 이어져야 한다), 색은 조금 짧게 감속으로 끊어 줘야 "바뀌었다"가 읽힌다.
struct CountdownRing: View {
    static let expiringSeconds = 5

    let remaining: Int
    let period: Int
    var lineWidth: CGFloat = 3

    private var expiring: Bool { remaining <= Self.expiringSeconds }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: lineWidth)
            arc(Color.green)
            arc(Color.codeExpiring)
                .opacity(expiring ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: expiring)
        }
    }

    /// 채움은 줄어드는 게 아니라 **차오른다**. 주기가 끝나면 값이 되돌아가면서 호도 거꾸로
    /// 풀리는데, 1초짜리 선형이 그 되돌림까지 이어 그려 줘서 툭 끊기지 않는다.
    ///
    /// 애니메이션을 호마다 안쪽에 다는 이유는 바깥의 투명도 애니메이션과 섞이지 않게
    /// 하기 위해서다 — 안쪽 것이 먼저 잡으므로 채움은 끝까지 1초 선형으로 남는다.
    private func arc(_ color: Color) -> some View {
        Circle()
            .trim(from: 0, to: CGFloat(period - remaining) / CGFloat(max(period, 1)))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 1), value: remaining)
    }
}
