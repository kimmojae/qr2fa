import SwiftUI

@main
struct qr2faApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("qr2fa", systemImage: "key.fill") {
            PopoverView()
                .environment(appDelegate.storageService)
        }
        .menuBarExtraStyle(.window)
    }
}
