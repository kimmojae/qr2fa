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
        Window("qr2fa", id: SettingsScene.windowID) {
            SettingsScene(appDelegate: appDelegate)
        }
    }
}

private enum SettingsTab: Hashable {
    case accounts
    case general
}

private struct SettingsScene: View {
    static let windowID = "settings"

    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var didBootstrap = false
    @State private var selectedTab: SettingsTab = .accounts

    var body: some View {
        Group {
            if selectedTab == .accounts {
                SettingsView()
            } else {
                GeneralSettingsView()
            }
        }
        .environment(appDelegate.storageService)
        .frame(minWidth: 760, idealWidth: 960, minHeight: 440, idealHeight: 580)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    Text("계정").tag(SettingsTab.accounts)
                    Text("일반").tag(SettingsTab.general)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
        .onAppear {
            // openWindow 액션을 AppDelegate에 넘겨 메뉴바에서 창을 열 수 있게 한다.
            appDelegate.presentSettings = { openWindow(id: Self.windowID) }
            // Window 씬은 실행 시 자동으로 열리므로, 첫 등장 때는 숨겨 메뉴바 앱처럼 동작한다.
            if !didBootstrap {
                didBootstrap = true
                dismissWindow(id: Self.windowID)
            }
        }
    }
}
