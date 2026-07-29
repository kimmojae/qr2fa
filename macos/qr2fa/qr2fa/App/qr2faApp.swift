import SwiftUI

/// Window 씬 id. AppDelegate가 AppKit 쪽에서 창을 식별할 때도 같은 문자열을 써야 하므로
/// 씬 구조체(private) 밖에 둔다 — 씬이 둘이라 "첫 번째 창"류의 추측이 통하지 않는다.
enum AppWindowID {
    static let onboarding = "onboarding"
    static let settings = "settings"
}

// SwiftUI 진입점.
// 설정 창(Window 씬)과 표준 메뉴(Edit: cmd+X/C/V, Quit: cmd+Q 등)는 SwiftUI가 관리한다.
// 윈도우를 SwiftUI가 소유하므로 NavigationSplitView의 빌트인 사이드바 토글이 타이틀바에
// 자동으로 나타난다. 상태바 메뉴(라이브 TOTP)는 AppDelegate가 AppKit으로 관리하고,
// 메뉴바의 "Settings…"는 아래에서 넘겨준 openWindow 액션으로 창을 연다.
@main
struct qr2faApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI는 실행 시 body에 선언된 Window 씬 중 "첫 번째" 것만 자동으로 연다 —
        // 여러 개를 선언한다고 전부 자동으로 열리는 게 아니다. 그래서 두 번째로 선언된
        // SettingsScene은 openWindow를 명시적으로 부르기 전까지는 절대 스스로 나타나지
        // 않는다. 메뉴바 "Settings…"가 쓰는 openWindow 액션 배선을 SettingsScene의
        // onAppear에 두면 그 onAppear 자체가 영영 실행되지 않아 배선이 죽는다 — 그래서
        // 이 배선은 항상 자동으로 열리는 OnboardingScene 쪽에 둔다.
        // 두 씬의 제목이 같으면 Window 메뉴에 구분되지 않는 항목이 둘 생긴다.
        Window("저장 위치 선택", id: AppWindowID.onboarding) {
            OnboardingScene(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("qr2fa", id: AppWindowID.settings) {
            SettingsScene(appDelegate: appDelegate)
        }
    }
}

private struct OnboardingScene: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
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
            dismissWindow(id: AppWindowID.onboarding)
        }
        .frame(width: 480, height: 420)
        .environment(appDelegate.storageService)
        .onAppear {
            // 이 씬은 실행 시 자동으로 열리는 유일한 Window 씬이다. 메뉴바에서 설정
            // 창을 여는 openWindow 액션은 (SettingsScene이 아니라) 여기서 넘겨야만
            // 온보딩 여부와 무관하게 항상 배선된다 — SettingsScene의 onAppear는
            // 명시적으로 openWindow(id: "settings")를 부르기 전까지 절대 실행되지
            // 않기 때문이다.
            appDelegate.presentSettings = { openWindow(id: AppWindowID.settings) }
            // 온보딩이 필요 없는 평소 실행에서는 곧장 닫아 메뉴바 앱처럼 동작하게 한다.
            if !didBootstrap {
                didBootstrap = true
                if !needsOnboarding {
                    dismissWindow(id: AppWindowID.onboarding)
                }
            }
        }
    }
}

private struct SettingsScene: View {
    let appDelegate: AppDelegate

    var body: some View {
        // 이 씬은 실행 시 자동으로 열리지 않는다(첫 번째로 선언된 건 OnboardingScene
        // 쪽이다) — 메뉴바 "Settings…"가 openWindow(id: "settings")를 호출할 때만
        // 나타난다. 그래서 예전처럼 onAppear에서 스스로 닫는 로직이 필요 없다.
        SettingsView()
            .environment(appDelegate.storageService)
            .frame(minWidth: 760, idealWidth: 960, minHeight: 440, idealHeight: 580)
    }
}
