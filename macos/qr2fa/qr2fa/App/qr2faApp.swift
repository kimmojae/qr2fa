import SwiftUI

/// Window 씬 id. AppDelegate가 AppKit 쪽에서 창을 식별할 때도 같은 문자열을 써야 하므로
/// 씬 구조체(private) 밖에 둔다 — 씬이 둘이라 "첫 번째 창"류의 추측이 통하지 않는다.
enum AppWindowID {
    static let onboarding = "onboarding"
    static let accounts = "accounts"
}

// SwiftUI 진입점.
// 계정 창(Window 씬), 설정 창(Settings 씬), 표준 메뉴(Edit: cmd+X/C/V, Quit: cmd+Q 등)를
// SwiftUI가 관리한다.
// 윈도우를 SwiftUI가 소유하므로 NavigationSplitView의 빌트인 사이드바 토글이 타이틀바에
// 자동으로 나타난다. 상태바 패널(라이브 TOTP)도 SwiftUI의 MenuBarExtra가 소유하고,
// 패널의 "Open qr2fa"와 "Settings…"는 아래에서 넘겨준 openWindow/openSettings 액션으로
// 각자의 창을 연다.
@main
struct qr2faApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// 펼쳐 둔 issuer는 패널이 닫혀도 유지돼야 하므로 패널 뷰보다 오래 사는 곳에 둔다.
    @State private var expansion = MenuBarExpansion()

    var body: some Scene {
        @Bindable var presence = appDelegate.presence
        return sceneBody(showsMenuBarIcon: $presence.showsMenuBarIcon)
    }

    @SceneBuilder
    private func sceneBody(showsMenuBarIcon: Binding<Bool>) -> some Scene {
        // `.menuBarExtraStyle(.window)`라야 임의의 SwiftUI 뷰를 그릴 수 있다. 기본값
        // (.menu)은 NSMenu로 렌더링돼서 호버 배경도, 제자리에서 펼쳐지는 그룹도 안 된다.
        // 메뉴바 아이콘은 끌 수 있다(설정 > 일반). Dock 아이콘과 둘 다 끌 수는 없다 —
        // 그 규칙은 `AppPresence`가 지킨다.
        MenuBarExtra(isInserted: showsMenuBarIcon) {
            MenuBarPanelContent(appDelegate: appDelegate, expansion: expansion)
        } label: {
            MenuBarLabel(appDelegate: appDelegate)
        }
        .menuBarExtraStyle(.window)

        // 계정 창을 먼저 선언한다. SwiftUI는 실행 시 body의 Window 씬 중 "첫 번째" 것만
        // 자동으로 여는데, 일반 앱이 실행되면 보여야 하는 건 앱의 내용이다.
        //
        // 그래도 창 열기 액션의 배선은 씬의 onAppear에 두지 않는다. 뒤에 선언된 씬은
        // 누가 열어 주기 전까지 onAppear가 영영 실행되지 않아 배선이 죽는다 — 배선은 앱이
        // 떠 있는 내내 존재하는 상태바 레이블에 둔다.
        // 두 씬의 제목이 같으면 Window 메뉴에 구분되지 않는 항목이 둘 생긴다.
        Window("qr2fa", id: AppWindowID.accounts) {
            AccountsScene(appDelegate: appDelegate)
        }

        Window("Qr2fa 시작하기", id: AppWindowID.onboarding) {
            OnboardingScene(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // 설정은 ⌘,로 여는 별도 창이다. 계정 목록은 환경설정이 아니라 앱의 내용이므로
        // 위의 창에 남는다.
        //
        // `Settings` 씬을 쓰면 창의 모양·위치·⌘, 등록을 시스템이 해 준다. 이 앱은 메뉴바
        // 앱(`LSUIElement`)이지만 창이 열려 있는 동안에는 `AppDelegate`가 활성화 정책을
        // `.regular`로 올리므로 앱 메뉴가 실제로 나타나고, 거기 "설정… ⌘,"가 함께 걸린다.
        Settings {
            SettingsWindowView()
                .environment(appDelegate.storageService)
                .environment(appDelegate.tagStyle)
                .environment(appDelegate.presence)
        }
        // `Settings` 씬의 기본값은 "내용 크기에 딱 맞춤"이라 드래그로 크기를 못 바꾼다.
        // 최소 크기만 지키고 그 위로는 열어 둔다.
        .windowResizability(.contentMinSize)
    }
}

/// 패널 내용. `openWindow`를 **자기 환경에서 직접** 꺼내 쓴다.
///
/// 예전엔 AppDelegate에 주입해 둔 클로저를 거쳤는데, 그 클로저가 배선되기 전이면 "Settings…"가
/// 조용히 아무 일도 하지 않았다. 뷰 안에서 쓸 수 있는 액션을 굳이 밖으로 내보냈다 다시
/// 들여올 이유가 없다. (AppKit 쪽 재실행 경로는 뷰가 없으므로 여전히 주입된 클로저를 쓴다.)
private struct MenuBarPanelContent: View {
    let appDelegate: AppDelegate
    let expansion: MenuBarExpansion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        MenuBarPanelView(
            storageService: appDelegate.storageService,
            expansion: expansion,
            clock: appDelegate.clock,
            tagStyle: appDelegate.tagStyle,
            openAccounts: { appDelegate.openAccounts { openWindow(id: AppWindowID.accounts) } },
            openGeneralSettings: { appDelegate.openGeneralSettings { openSettings() } },
            runMigration: { appDelegate.runMigration() }
        )
    }
}

/// 상태바 아이콘. 그리는 일 말고 **창 열기 액션을 AppDelegate에 배선하는** 일을 겸한다.
///
/// 이 배선이 여기 있는 이유: 예전엔 온보딩 씬의 `onAppear`에 있었는데, 그건 "실행 시 첫
/// Window 씬이 자동으로 열린다"는 전제에 기대고 있었다. `MenuBarExtra`가 앞에 생기면서
/// 그 전제가 깨져 배선이 영영 nil로 남았고, 메뉴바의 창 열기와 첫 실행 온보딩이
/// 둘 다 조용히 죽었다. 상태바 레이블은 앱이 떠 있는 내내 존재하므로 여기가 유일하게
/// 확실한 자리다.
private struct MenuBarLabel: View {
    let appDelegate: AppDelegate

    var body: some View {
        // 템플릿 렌더링이라 라이트/다크 메뉴바를 자동으로 따라간다.
        Image("MenuBarIcon")
            .renderingMode(.template)
            .wiringWindowActions(into: appDelegate)
    }
}

private extension View {
    /// 창 열기 액션을 AppDelegate에 배선하고, 실행 직후에 보여줄 창을 연다.
    ///
    /// 메뉴바 레이블과 계정 창 **양쪽**에 붙인다. 둘 중 어느 쪽도 항상 존재한다고 보장할 수
    /// 없기 때문이다 — 메뉴바 아이콘은 설정에서 끌 수 있고, 계정 창은 로그인 항목으로
    /// 떠올랐을 때 열리지 않는다. 배선이 없으면 "Settings…"가 조용히 아무 일도 안 한다.
    /// 두 번 불려도 무해하도록 대입은 멱등이고, 실행 시 창 열기는 한 번만 실행된다.
    func wiringWindowActions(into appDelegate: AppDelegate) -> some View {
        modifier(WindowActionWiring(appDelegate: appDelegate))
    }
}

private struct WindowActionWiring: ViewModifier {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onAppear {
            appDelegate.presentAccounts = { openWindow(id: AppWindowID.accounts) }
            appDelegate.presentOnboarding = { openWindow(id: AppWindowID.onboarding) }
            appDelegate.presentGeneralSettings = { openSettings() }
            appDelegate.presentLaunchWindow()
        }
    }
}

private struct OnboardingScene: View {
    let appDelegate: AppDelegate
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        // 이 씬은 더 이상 자동으로 열리지 않는다. 저장 위치가 없을 때 AppDelegate가
        // 명시적으로 연다 — 그래서 예전처럼 스스로 닫는 로직이 필요 없다.
        OnboardingView {
            dismissWindow(id: AppWindowID.onboarding)
        }
        .frame(width: 560, height: 270)
        .environment(appDelegate.storageService)
    }
}

private struct AccountsScene: View {
    let appDelegate: AppDelegate

    var body: some View {
        AccountsWindowView()
            .environment(appDelegate.storageService)
            .environment(appDelegate.clock)
            .environment(appDelegate.tagStyle)
            .frame(minWidth: 760, idealWidth: 960, minHeight: 440, idealHeight: 580)
            // 메뉴바 아이콘을 꺼 두면 그쪽 배선이 영영 실행되지 않는다. 그때는 이 창이
            // 실행과 함께 열리므로 여기가 배선이 닿는 자리다.
            .wiringWindowActions(into: appDelegate)
    }
}
