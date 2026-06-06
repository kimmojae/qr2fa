import AppKit

// 순수 AppKit 진입점.
// 창·메뉴·상태바는 모두 AppDelegate가 직접 관리하며,
// SwiftUI 뷰(SettingsView 등)는 NSHostingController로 AppKit 창에 얹는다.
@main
enum AppMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
