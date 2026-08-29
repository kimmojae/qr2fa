import AppKit
import SwiftUI
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let storageService = StorageService()
    /// SwiftUI 쪽에서 주입하는 설정 창 열기 액션(openWindow).
    var presentSettings: (() -> Void)?
    private var statusItem: NSStatusItem!
    private var submenuDelegates: [SubMenuDelegate] = []
    private weak var settingsWindow: NSWindow?

    // 메뉴바 앱이므로 설정 창을 닫아도 앱이 종료되면 안 된다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Spotlight/Dock에서 이미 실행 중인 앱을 다시 "실행"했을 때.
    ///
    /// 기본 동작에 맡기면 AppKit이 예전에 order-out된 창을 전부 다시 앞으로 꺼낸다. 온보딩 창은
    /// `dismissWindow`로 화면에서만 내려간 상태(창 객체는 계속 살아 있다)라, 저장 위치를 이미 고른
    /// 사용자에게도 "MFA 데이터를 어디에 저장할까요?"가 다시 뜬다 — 로그인 항목으로 떠 있는 앱을
    /// Spotlight에서 켜면 매번 재현된다. 메뉴바 앱에서 재실행의 의미는 설정 창을 보여 달라는
    /// 것이므로 직접 처리한다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // 아직 위치를 고르지 않았다면 온보딩 창이 앞으로 나오는 게 맞다.
        guard !storageService.needsLocationChoice else { return true }
        hideOnboardingWindow()
        openSettings()
        return false
    }

    /// `false`를 돌려줘도 AppKit이 이미 창을 꺼내 놓은 경우가 있어, 다음 런루프에서 한 번 더 내린다.
    private func hideOnboardingWindow() {
        onboardingSceneWindow()?.orderOut(nil)
        DispatchQueue.main.async { [weak self] in
            self?.onboardingSceneWindow()?.orderOut(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // 메인 메뉴는 SwiftUI(App 씬)가 표준 구성으로 만든다. 직접 덮어쓰지 않아야
        // Edit 메뉴(cmd+X/C/V)와 Quit(cmd+Q)가 살아있다.
        do { try storageService.load() } catch {
            NSLog("qr2fa: load failed: \(error)")
        }
        setupStatusItem()
        observeAccounts()
    }

    /// SwiftUI Settings 씬이 만든 창.
    ///
    /// 예전엔 "메인이 될 수 있는 첫 창"으로 찾았는데, 온보딩 씬이 생기면서 그 전제가 깨졌다 —
    /// 온보딩 창이 먼저 만들어지고 `dismissWindow`는 order-out일 뿐 `NSApp.windows`에서
    /// 빼주지 않아, 닫힌 온보딩 창을 집어 willClose 옵저버가 엉뚱한 창에 붙었다(설정 창을
    /// 닫아도 `.accessory`로 안 돌아가 Dock 아이콘이 남았다). 씬 id로 정확히 고른다.
    /// SwiftUI는 씬 id를 창의 identifier와 frameAutosaveName에 넣는데, 어느 쪽이 채워질지는
    /// 보장되지 않아 둘 다 본다.
    private func settingsSceneWindow() -> NSWindow? { sceneWindow(id: AppWindowID.settings) }

    private func onboardingSceneWindow() -> NSWindow? { sceneWindow(id: AppWindowID.onboarding) }

    private func sceneWindow(id: String) -> NSWindow? {
        NSApp.windows.first {
            $0.identifier?.rawValue == id || $0.frameAutosaveName == id
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "MenuBarIcon")
        icon?.isTemplate = true
        icon?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = icon
        rebuildMenu()
    }

    private func observeAccounts() {
        withObservationTracking {
            _ = storageService.accounts
            _ = storageService.state
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.rebuildMenu()
                self?.observeAccounts()
            }
        }
    }

    private func rebuildMenu() {
        submenuDelegates = []
        let menu = NSMenu()

        switch storageService.state {
        case .unlocked:
            break   // 아래 기존 계정 항목 구성으로 진행
        case .locked:
            let item = menu.addItem(withTitle: "잠김 — 계정 파일을 열 열쇠가 없습니다",
                         action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(.separator())
        case .needsMigration:
            let item = NSMenuItem(title: "저장 방식을 암호화로 바꾸기…",
                                  action: #selector(runMigration), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        case .unreadable(let message):
            let item = menu.addItem(withTitle: message, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(.separator())
        }

        let groups = groupedAccounts()

        if groups.isEmpty {
            let empty = NSMenuItem(title: "No accounts", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (issuer, accounts) in groups {
                let title = issuer.count > 18 ? String(issuer.prefix(16)) + "…" : issuer
                let issuerItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: issuer)
                var pairs: [(NSMenuItem, AccountMenuItemView)] = []

                for account in accounts {
                    let item = NSMenuItem()
                    item.target = self
                    item.action = #selector(noOp)
                    let view = AccountMenuItemView(account: account)
                    item.view = view
                    pairs.append((item, view))
                    submenu.addItem(item)
                }

                let delegate = SubMenuDelegate(pairs: pairs)
                submenu.delegate = delegate
                submenuDelegates.append(delegate)

                issuerItem.submenu = submenu
                menu.addItem(issuerItem)
            }
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        menu.addItem(settingsItem)
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func groupedAccounts() -> [(String, [Account])] {
        var dict: [String: [Account]] = [:]
        for acc in storageService.accounts {
            dict[acc.displayIssuer, default: []].append(acc)
        }
        // 이름순이 아니라 사용자가 설정 창에서 정한 순서(= 저장 순서)를 따른다.
        return AccountOrdering.issuers(in: storageService.accounts).map { ($0, dict[$0]!) }
    }

    @objc private func openSettings() {
        // 상태바 메뉴가 닫힌 뒤(다음 런루프) 실행한다.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.setActivationPolicy(.regular)
            // SwiftUI가 소유한 Window 씬을 openWindow 액션으로 연다.
            self.presentSettings?()
            self.finishPresentingSettings(attemptsLeft: 20)
        }
    }

    /// 설정 창이 실제로 생긴 뒤에 앞으로 꺼내고 앱을 활성화한다.
    ///
    /// 예전엔 `openWindow` 직후 다음 런루프에 딱 한 번 창을 찾고, 못 찾으면 그냥 return이었다.
    /// 그런데 (1) `presentSettings` 배선은 온보딩 씬의 onAppear에서 이뤄지므로 로그인 항목으로 막
    /// 떠오른 직후엔 아직 nil일 수 있고, (2) `openWindow`가 만드는 창이 그 한 번의 확인 시점에
    /// 항상 있는 것도 아니며, (3) `.accessory` → `.regular`로 바꾼 직후의 `activate`는 자주
    /// 무시된다. 그래서 첫 클릭이 아무 일도 안 하거나 설정 창이 다른 앱 창 뒤에서 열려 "두 번
    /// 눌러야 되는" 증상이 났다. 창이 나타날 때까지 짧게 재시도하고, 찾은 뒤에 order-front와
    /// activate를 한다.
    private func finishPresentingSettings(attemptsLeft: Int) {
        guard let window = settingsSceneWindow() else {
            guard attemptsLeft > 0 else {
                NSLog("qr2fa: settings window did not appear")
                // 창 없이 Dock 아이콘만 남기지 않는다.
                NSApp.setActivationPolicy(.accessory)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                // 배선이 늦게 끝났을 수 있으니 다시 부른다. 이미 열린 창에 대해선 무해하다.
                self.presentSettings?()
                self.finishPresentingSettings(attemptsLeft: attemptsLeft - 1)
            }
            return
        }
        // 창이 뜬 뒤, 닫힘을 관찰해 다시 액세서리 모드로 돌리고 위치를 보정한다.
        if settingsWindow !== window {
            settingsWindow = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(settingsWindowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }
        window.toolbarStyle = .unified
        // 씬이 복원한 위치가 화면 밖이면 가운데로.
        if !NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func settingsWindowWillClose(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func noOp() {}

    @objc private func runMigration() {
        do {
            try storageService.migrateToEncrypted()
            let alert = NSAlert()
            alert.messageText = "계정 파일을 암호화했습니다"
            alert.informativeText = """
                열쇠는 이 Mac의 Keychain에 보관됩니다.

                예전 평문 파일은 지우지 않고 남겨뒀습니다:
                \(storageService.lastMigrationBackupPath ?? "-")

                정상 동작을 확인한 뒤 직접 지우셔야 실제로 안전해집니다.
                """
            alert.runModal()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

// MARK: - SubMenuDelegate

final class SubMenuDelegate: NSObject, NSMenuDelegate {
    private let pairs: [(NSMenuItem, AccountMenuItemView)]
    private var timer: Timer?

    init(pairs: [(NSMenuItem, AccountMenuItemView)]) {
        self.pairs = pairs
    }

    func menuWillOpen(_ menu: NSMenu) {
        pairs.forEach { $0.1.updateCode() }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pairs.forEach { $0.1.updateCode() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func menuDidClose(_ menu: NSMenu) {
        timer?.invalidate()
        timer = nil
        pairs.forEach { $0.1.setHighlighted(false) }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for (menuItem, view) in pairs {
            view.setHighlighted(menuItem === item)
        }
    }
}
