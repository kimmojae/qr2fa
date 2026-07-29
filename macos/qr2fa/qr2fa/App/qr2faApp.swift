import SwiftUI

// SwiftUI 진입점.
// 설정 창(Window 씬)과 표준 메뉴(Edit: cmd+X/C/V, Quit: cmd+Q 등)는 SwiftUI가 관리한다.
// 윈도우를 SwiftUI가 소유하므로 NavigationSplitView의 빌트인 사이드바 토글이 타이틀바에
// 자동으로 나타난다. 상태바 메뉴(라이브 TOTP)는 AppDelegate가 AppKit으로 관리하고,
// 메뉴바의 "Settings…"는 아래에서 넘겨준 openWindow 액션으로 창을 연다.
@main
struct qr2faApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 온보딩을 설정과 같은 Window 씬(같은 id)에 얹었더니, macOS가 그 id로 저장해 둔
        // 예전 설정 창 크기(NSWindow 프레임 자동저장은 창 id 단위)가 온보딩의 작은
        // .frame()보다 우선 적용돼 창 주위에 빈 공간이 남는 문제가 있었다. 그래서
        // 온보딩은 자기만의 id를 가진 별도 Window 씬으로 분리한다 — 자동저장 기록이
        // 아예 없으니 .windowResizability(.contentSize)가 콘텐츠 크기 그대로 창을
        // 잡아준다.
        Window("qr2fa", id: OnboardingScene.windowID) {
            OnboardingScene(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("qr2fa", id: SettingsScene.windowID) {
            SettingsScene(appDelegate: appDelegate)
        }
    }
}

private struct OnboardingScene: View {
    static let windowID = "onboarding"

    let appDelegate: AppDelegate
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var didBootstrap = false
    @State private var needsOnboarding: Bool

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        _needsOnboarding = State(initialValue: appDelegate.storageService.needsLocationChoice)
    }

    var body: some View {
        OnboardingView {
            needsOnboarding = false
            dismissWindow(id: Self.windowID)
        }
        .frame(width: 480, height: 420)
        .environment(appDelegate.storageService)
        .onAppear {
            // Window 씬은 실행 시 자동으로 열린다. 온보딩이 필요 없는 평소 실행에서는
            // (이미 저장 위치를 고른 적이 있으면) 곧장 닫아 메뉴바 앱처럼 동작하게 한다.
            if !didBootstrap {
                didBootstrap = true
                if !needsOnboarding {
                    dismissWindow(id: Self.windowID)
                }
            }
        }
    }
}

private struct SettingsScene: View {
    static let windowID = "settings"

    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var didBootstrap = false

    var body: some View {
        SettingsView()
            .environment(appDelegate.storageService)
            .frame(minWidth: 760, idealWidth: 960, minHeight: 440, idealHeight: 580)
            .onAppear {
                // openWindow 액션을 AppDelegate에 넘겨 메뉴바에서 창을 열 수 있게 한다.
                appDelegate.presentSettings = { openWindow(id: Self.windowID) }
                // Window 씬은 실행 시 자동으로 열리므로, 첫 등장 때는 숨겨 메뉴바 앱처럼
                // 동작한다. 온보딩이 필요한 경우는 OnboardingScene이 대신 뜨므로 이 창은
                // 그 경우에도 그대로 닫아 둔다.
                if !didBootstrap {
                    didBootstrap = true
                    dismissWindow(id: Self.windowID)
                }
            }
    }
}
