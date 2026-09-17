import AppKit
import SwiftUI

/// 상태바 아이콘을 누르면 나오는 패널.
///
/// 코드를 복사해도 **닫지 않는다** — 여러 개를 연달아 복사하는 경우가 있고, 닫아 버리면
/// 복사됐다는 표시를 볼 새도 없이 사라진다.
struct MenuBarPanelView: View {
    let storageService: StorageService
    let expansion: MenuBarExpansion
    /// 1초에 한 번 갱신되는 "지금". 코드·남은 시간·복사 표시가 전부 이 값 하나에서
    /// 파생되므로 한 틱 안에서는 화면 전체가 같은 시각을 본다. 설정 창도 **같은** 시계를
    /// 보므로 둘을 나란히 띄워도 남은 시간이 어긋나지 않는다.
    let clock: TOTPClock
    let tagStyle: TagStyle
    let openAccounts: () -> Void
    let openGeneralSettings: () -> Void
    let runMigration: () -> Void

    private var now: Date { clock.now }

    private var accounts: [Account] { storageService.accounts }
    private var groups: [MenuBarGroup] { MenuBarList.groups(for: accounts) }
    /// 주기가 섞여 있으면 헤더 하나로 대표할 수 없다.
    private var commonPeriod: Int? { MenuBarList.commonPeriod(in: accounts) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        // HurryPorter 팝오버(`PopoverView`)와 같은 값. 둘 다 메뉴바에 사는 앱이라 번갈아
        // 열면 폭 차이가 바로 눈에 걸리는데, 그 차이에 담을 뜻이 없다.
        .frame(width: 340)
        .onAppear {
            expansion.prune(keeping: AccountOrdering.issuers(in: accounts))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(appDisplayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if let period = commonPeriod {
                countdown(period: period)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }

    /// 숫자는 두지 않는다. "23s"를 읽어서 하는 판단은 "지금 복사해도 되나" 하나뿐인데,
    /// 그건 링이 얼마나 찼는지와 5초부터의 주황이 이미 말해 준다. 설정 창과 같은 링이다.
    private func countdown(period: Int) -> some View {
        let remaining = TOTPGenerator.remainingSeconds(date: now, period: period)
        return CountdownRing(remaining: remaining, period: period, lineWidth: 2)
            .frame(width: 13, height: 13)
            .help("\(remaining)초 후 코드가 바뀝니다")
            .accessibilityLabel("코드 갱신까지 \(remaining)초")
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 1) {
            if let notice = vaultNotice {
                notice
            }
            if accounts.isEmpty {
                empty
            } else {
                ForEach(groups) { group in
                    MenuBarIssuerGroup(group: group,
                                       showsOwnCountdown: commonPeriod == nil,
                                       now: now,
                                       tagStyle: tagStyle,
                                       isExpanded: expansion.isExpanded(group.issuer),
                                       toggle: { expansion.toggle(group.issuer) })
                }
            }
        }
        .padding(6)
    }

    private var empty: some View {
        Text(storageService.state.isUnlocked ? "계정이 없습니다" : "계정을 읽을 수 없습니다")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
    }

    /// 잠김·마이그레이션 필요·읽기 실패는 계정 목록보다 먼저 말해 준다. 목록이 비어 있는
    /// 이유가 "계정이 없어서"가 아닐 수 있고, 그 차이는 사용자가 알아야 한다.
    @ViewBuilder
    private var vaultNotice: (some View)? {
        switch storageService.state {
        case .unlocked:
            EmptyView()
        case .locked:
            noticeRow("lock.fill", "잠김 — 계정 파일을 열 열쇠가 없습니다", action: nil)
        case .needsMigration:
            noticeRow("arrow.up.forward.square", "저장 방식을 암호화로 바꾸기…", action: runMigration)
        case .unreadable(let message):
            noticeRow("exclamationmark.triangle.fill", message, action: nil)
        }
    }

    @ViewBuilder
    private func noticeRow(_ symbol: String, _ text: String, action: (() -> Void)?) -> some View {
        let content = HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10))
            Text(text)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { content }
                .buttonStyle(MenuBarRowButtonStyle(isHovered: false))
        } else {
            content
        }
    }

    // MARK: - Footer

    /// 가는 곳이 둘이다. **Open**은 계정을 다루는 창, **Settings…**는 ⌘,로 여는
    /// 설정 창. macOS에서 ⌘,는 "앱 환경설정"이라는 뜻이 고정된 단축키라 계정 창에 붙일 수 없다.
    private var footer: some View {
        HStack(spacing: 12) {
            Button { openAccounts() } label: {
                // 무엇을 여는지는 패널 머리에 있는 앱 이름이 이미 말해 준다.
                footerLabel("Open", shortcut: "\u{2318} N")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)

            Spacer(minLength: 0)

            Button { openGeneralSettings() } label: {
                footerLabel("Settings…", shortcut: "\u{2318} ,")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)

            Button { NSApplication.shared.terminate(nil) } label: {
                footerLabel("Quit", shortcut: "\u{2318} Q")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    /// 기존 NSMenu가 그랬듯 단축키를 함께 보여준다. 표시만이 아니라 실제로 동작한다.
    /// 단축키가 없는 항목은 그 자리를 비워 둔다 — 없는 걸 지어내지 않는다.
    private func footerLabel(_ title: String, shortcut: String?) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if let shortcut {
                Text(shortcut)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

private extension StorageService.VaultState {
    var isUnlocked: Bool {
        if case .unlocked = self { return true }
        return false
    }
}
