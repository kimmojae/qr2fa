import AppKit
import SwiftUI

/// 메뉴바 패널의 계정 한 줄.
///
/// 행 **어디를 눌러도** 코드가 복사된다. 오른쪽 복사 아이콘은 호버할 때만 나타나는 보조
/// 표시이지 정확히 겨눠야 하는 과녁이 아니다.
struct MenuBarAccountRow: View {
    let account: Account
    /// 계정마다 주기가 다를 때만 참 — 그때는 헤더의 공통 남은 시간이 거짓말이 되므로
    /// 행이 각자의 남은 시간을 들고 있어야 한다.
    var showsOwnCountdown: Bool = false
    let now: Date
    let tagStyle: TagStyle

    @State private var isHovered = false
    @State private var copiedAt: Date?

    /// 복사 표시가 떠 있는 동안인지. 타이머 틱마다 다시 계산되므로 별도 스케줄링이 없다 —
    /// 1초에 한 번은 무조건 다시 그려지는 뷰라 여기에 얹는 게 가장 적은 기계장치다.
    private var isCopied: Bool {
        guard let copiedAt else { return false }
        return now.timeIntervalSince(copiedAt) < 1.5
    }

    private var rawCode: String {
        (try? TOTPGenerator.generate(account: account, date: now)) ?? "------"
    }

    private var codeColor: Color {
        if isCopied { return .codeCopied }
        return isHovered ? .codeAccent : .primary
    }

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 10) {
                Text(TOTPGenerator.formattedCode(rawCode))
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(codeColor)
                    .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // 보여줄 게 없으면 줄 자체를 만들지 않는다. 빈 채로 높이만 잡아 두면
                    // 태그 없는 계정의 행이 이유 없이 헐거워 보인다.
                    if hasMeta { metaLine }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailingSlot
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            // 높이를 내용에 맡기면 호버/복사로 오른쪽 슬롯이 바뀔 때마다 행이 출렁인다.
            // 태그 유무만으로 결정되는 두 값 중 하나로 못 박는다.
            .frame(height: hasMeta ? 33 : 23)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuBarRowButtonStyle(isHovered: isHovered))
        // 코드는 한 자리씩 읽히면 알아들을 수 없다. 무엇을 누르는 버튼인지로 읽어 준다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(account.displayIssuer) \(account.name) 인증 코드 복사")
        .accessibilityValue(TOTPGenerator.formattedCode(rawCode))
        .onHover { inside in isHovered = inside }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    /// issuer는 이미 그룹 헤더에 있고 계정 이름은 위 줄에 있으므로, 메타 줄에 올 것은
    /// 태그뿐이다. 태그가 없으면 줄 자체를 만들지 않는다.
    private var hasMeta: Bool { !account.tag.isEmpty }

    /// 태그는 계정의 것이므로 계정 행에만 둔다(접힌 그룹 헤더에는 없다).
    /// 색은 하나뿐이다 — 태그별 색은 없고, 그 하나를 일반 설정에서 고른다.
    private var metaLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag")
            Text(account.tag)
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(tagStyle.color)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// 복사 아이콘과 (주기가 섞였을 때의) 남은 시간이 같은 자리를 쓴다.
    /// 폭과 높이를 고정해야 호버할 때 행이 출렁이지 않는다.
    private var trailingSlot: some View {
        Group {
            if isCopied {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.codeCopied)
            } else if isHovered {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            } else if showsOwnCountdown {
                // 패널 헤더와 같은 링 — 같은 뜻을 한 화면에서 두 가지 모양으로 보이면 안 된다.
                CountdownRing(remaining: TOTPGenerator.remainingSeconds(date: now,
                                                                        period: account.period),
                              period: account.period,
                              lineWidth: 1.5)
                    .frame(width: 11, height: 11)
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .frame(width: 24, height: 20, alignment: .trailing)
    }

    private func copy() {
        guard let code = try? TOTPGenerator.generate(account: account, date: Date()) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copiedAt = Date()
    }
}

/// 행 배경. 호버는 SwiftUI가 `ButtonStyle`에 주지 않으므로 바깥에서 받아 온다.
///
/// 누르는 동안 배경만 한 단계 진해진다 — 0.1초짜리 상태라 그 이상 바꾸면 과하다.
struct MenuBarRowButtonStyle: ButtonStyle {
    var isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(background(configuration.isPressed))
            )
    }

    private func background(_ pressed: Bool) -> Color {
        if pressed { return .primary.opacity(0.14) }
        return isHovered ? .primary.opacity(0.07) : .clear
    }
}
