import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    let storageService = StorageService()
    private var fileWatcher: FileWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            try storageService.load()
        } catch {
            NSLog("qr2fa: failed to load accounts: \(error)")
        }

        fileWatcher = FileWatcher(path: storageService.storagePath) { [weak self] in
            guard let self else { return }
            try? self.storageService.load()
        }
    }
}
