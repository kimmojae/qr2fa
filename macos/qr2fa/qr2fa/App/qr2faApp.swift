import SwiftUI

@main struct qr2faApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings 창은 AppDelegate에서 NSWindow로 직접 관리
        WindowGroup { EmptyView() }
            .defaultSize(width: 0, height: 0)
            .commandsRemoved()
    }
}
