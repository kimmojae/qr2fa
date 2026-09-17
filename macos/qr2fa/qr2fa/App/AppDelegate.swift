import AppKit
import SwiftUI
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let storageService = StorageService()
    /// 메뉴바 패널과 계정 창이 같은 초를 보게 하는 공용 시계. 화면마다 타이머를 돌리면
    /// 둘을 나란히 띄웠을 때 남은 시간이 어긋난다.
    let clock = TOTPClock()
    /// 태그 대표 색. 설정 창에서 고르고 메뉴바가 같이 따라야 하므로 여기서 하나만 만든다.
    let tagStyle = TagStyle()
    /// 이 앱이 Dock과 메뉴바 중 어디에 보이는지. 활성화 정책을 정하는 곳은 여기 하나뿐이다.
    let presence = AppPresence()
    /// SwiftUI 쪽에서 주입하는 창 열기 액션(openWindow). 상태바 레이블이 배선한다.
    var presentAccounts: (() -> Void)?
    var presentOnboarding: (() -> Void)?
    /// ⌘,로 여는 설정 창. 메뉴바 패널의 "Settings…"가 배선한다.
    var presentGeneralSettings: (() -> Void)?

    // 창을 다 닫아도 앱이 종료되면 안 된다. 메뉴바 아이콘이 남아 있고, 거기서 코드를
    // 복사하는 게 이 앱의 일상 동작이다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Spotlight/Dock에서 이미 실행 중인 앱을 다시 "실행"했을 때.
    ///
    /// 기본 동작에 맡기면 AppKit이 예전에 order-out된 창을 전부 다시 앞으로 꺼낸다. 온보딩 창은
    /// `dismissWindow`로 화면에서만 내려간 상태(창 객체는 계속 살아 있다)라, 저장 위치를 이미 고른
    /// 사용자에게도 "MFA 데이터를 어디에 저장할까요?"가 다시 뜬다 — 로그인 항목으로 떠 있는 앱을
    /// Spotlight에서 켜면 매번 재현된다. 재실행의 의미는 계정 창을 보여 달라는 것이므로
    /// 직접 처리한다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // 아직 위치를 고르지 않았다면 온보딩 창이 앞으로 나오는 게 맞다.
        guard !storageService.needsLocationChoice else { return true }
        hideOnboardingWindow()
        openAccounts()
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
        // 활성화 정책은 설정이 정한다. 창을 열고 닫을 때마다 바꾸지 않는다.
        presence.apply()
        // 메인 메뉴는 SwiftUI(App 씬)가 표준 구성으로 만든다. 직접 덮어쓰지 않아야
        // Edit 메뉴(cmd+X/C/V)와 Quit(cmd+Q)가 살아있다.
        do { try storageService.load() } catch {
            NSLog("qr2fa: load failed: \(error)")
        }
        launchedByUser = Self.isUserLaunch(notification)
    }

    /// 사용자가 직접 실행한 것인지. 로그인 항목으로 떠오른 경우는 거짓이다.
    ///
    /// 일반 앱은 실행하면 창이 떠야 하지만, 로그인할 때마다 계정 창이 튀어나오면 안 된다.
    /// 그건 실행이 아니라 대기다.
    private(set) var launchedByUser = true
    private var didPresentLaunchWindow = false

    private static func isUserLaunch(_ notification: Notification) -> Bool {
        // 이 키가 거짓이면 시스템이 띄운 것이다(로그인 항목, 재개 등). 키가 아예 없는
        // 경우도 있는데, 그때는 사용자가 실행한 것으로 본다 — 창이 안 뜨는 쪽보다
        // 뜨는 쪽이 덜 당황스럽다.
        guard let value = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey]
                as? Bool else { return true }
        return value
    }

    /// SwiftUI가 만든 계정 창(3열).
    ///
    /// 예전엔 "메인이 될 수 있는 첫 창"으로 찾았는데, 온보딩 씬이 생기면서 그 전제가 깨졌다 —
    /// 온보딩 창이 먼저 만들어지고 `dismissWindow`는 order-out일 뿐 `NSApp.windows`에서
    /// 빼주지 않아, 닫힌 온보딩 창을 집어 willClose 옵저버가 엉뚱한 창에 붙었다(창을
    /// 닫아도 `.accessory`로 안 돌아가 Dock 아이콘이 남았다). 씬 id로 정확히 고른다.
    /// SwiftUI는 씬 id를 창의 identifier와 frameAutosaveName에 넣는데, 어느 쪽이 채워질지는
    /// 보장되지 않아 둘 다 본다.
    private func accountsSceneWindow() -> NSWindow? { sceneWindow(id: AppWindowID.accounts) }

    private func onboardingSceneWindow() -> NSWindow? { sceneWindow(id: AppWindowID.onboarding) }

    private func sceneWindow(id: String) -> NSWindow? {
        NSApp.windows.first {
            $0.identifier?.rawValue == id || $0.frameAutosaveName == id
        }
    }

    /// SwiftUI `Settings` 씬이 만든 창. identifier를 우리가 정하지 않고 SwiftUI가 붙이므로
    /// (`com_apple_SwiftUI_Settings_window`) 그 이름으로 찾는다.
    private func generalSettingsSceneWindow() -> NSWindow? {
        NSApp.windows.first {
            ($0.identifier?.rawValue ?? "").contains("Settings")
                || $0.frameAutosaveName.contains("Settings")
        }
    }

    /// 실행 직후에 무엇을 보여줄지. 배선이 끝난 직후에 불린다.
    ///
    /// 저장 위치를 아직 안 골랐으면 온보딩, 아니면 계정 창. 단 로그인 항목으로 떠오른
    /// 경우에는 아무것도 열지 않는다 — 메뉴바 아이콘만 조용히 자리를 잡는다.
    func presentLaunchWindow() {
        // 배선이 두 곳에 있으므로 두 번 불릴 수 있다. 창을 두 번 여는 건 무해하지만,
        // 온보딩을 이미 닫은 뒤에 다시 띄우는 건 곤란하다.
        guard !didPresentLaunchWindow else { return }
        didPresentLaunchWindow = true
        guard storageService.needsLocationChoice else {
            if launchedByUser { openAccounts() }
            return
        }
        presentOnboarding?()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.onboardingSceneWindow()?.makeKeyAndOrderFront(nil)
        }
    }

    /// 계정 창을 여는 통로.
    ///
    /// `present`를 주면 그걸 쓴다 — 패널처럼 자기 `openWindow`를 가진 뷰는 주입된 클로저에
    /// 기대지 않는 게 안전하다. AppKit 쪽(Dock/Spotlight 재실행)은 뷰가 없어서 생략한다.
    func openAccounts(present: (() -> Void)? = nil) {
        show(open: present ?? { [weak self] in self?.presentAccounts?() },
             find: { [weak self] in self?.accountsSceneWindow() },
             name: "accounts")
    }

    /// 설정 창(⌘,)을 여는 통로. 계정 창과 같은 절차를 탄다 — 메뉴바 앱은 `.accessory`로
    /// 떠 있어서, 창을 여는 것만으로는 앞으로 나오지 않는다.
    func openGeneralSettings(present: (() -> Void)? = nil) {
        show(open: present ?? { [weak self] in self?.presentGeneralSettings?() },
             find: { [weak self] in self?.generalSettingsSceneWindow() },
             name: "settings")
    }

    private func show(open: @escaping () -> Void,
                      find: @escaping () -> NSWindow?,
                      name: String) {
        // 패널이 닫힌 뒤(다음 런루프) 실행한다.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            open()
            self.finishPresenting(open: open, find: find, name: name, attemptsLeft: 20)
        }
    }

    /// 창이 실제로 생긴 뒤에 앞으로 꺼내고 앱을 활성화한다.
    ///
    /// 예전엔 `openWindow` 직후 다음 런루프에 딱 한 번 창을 찾고, 못 찾으면 그냥 return이었다.
    /// 그런데 (1) `presentAccounts` 배선은 상태바 레이블의 onAppear에서 이뤄지므로 로그인 항목으로 막
    /// 떠오른 직후엔 아직 nil일 수 있고, (2) `openWindow`가 만드는 창이 그 한 번의 확인 시점에
    /// 항상 있는 것도 아니며, (3) `.accessory` → `.regular`로 바꾼 직후의 `activate`는 자주
    /// 무시된다. 그래서 첫 클릭이 아무 일도 안 하거나 설정 창이 다른 앱 창 뒤에서 열려 "두 번
    /// 눌러야 되는" 증상이 났다. 창이 나타날 때까지 짧게 재시도하고, 찾은 뒤에 order-front와
    /// activate를 한다.
    private func finishPresenting(open: @escaping () -> Void,
                                  find: @escaping () -> NSWindow?,
                                  name: String,
                                  attemptsLeft: Int) {
        guard let window = find() else {
            guard attemptsLeft > 0 else {
                NSLog("qr2fa: \(name) window did not appear")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                // 창이 아직 안 생겼을 수 있으니 다시 부른다. 이미 열린 창에 대해선 무해하다.
                open()
                self.finishPresenting(open: open, find: find, name: name,
                                      attemptsLeft: attemptsLeft - 1)
            }
            return
        }
        // toolbarStyle은 건드리지 않는다. `.unified`로 바꿔 두면 SwiftUI가 분할 열마다
        // 나눠 둔 툴바 구역이 창 툴바 하나로 합쳐진다 — 계정 창의 +·검색·편집이 열을
        // 따라가려면 기본값이어야 한다.
        // 씬이 복원한 위치가 화면 밖이면 가운데로.
        if !NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func runMigration() {
        do {
            let backupPath = try storageService.migrateToEncrypted()
            let alert = NSAlert()
            alert.messageText = "계정 파일을 암호화했습니다"
            alert.informativeText = """
                열쇠는 이 Mac의 Keychain에 보관됩니다.

                예전 평문 파일은 지우지 않고 남겨뒀습니다:
                \(backupPath ?? "-")

                정상 동작을 확인한 뒤 직접 지우셔야 실제로 안전해집니다.
                """
            alert.runModal()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
