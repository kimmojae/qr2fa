import AppKit
import SwiftUI
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let storageService = StorageService()
    private var statusItem: NSStatusItem!
    private var submenuDelegates: [SubMenuDelegate] = []
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // SwiftUI WindowGroup이 자동 생성하는 빈 창을 닫음
        NSApp.windows.forEach { $0.close() }
        setupMainMenu()
        do { try storageService.load() } catch {
            NSLog("qr2fa: load failed: \(error)")
        }
        setupStatusItem()
        observeAccounts()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "dot.viewfinder", accessibilityDescription: "qr2fa")
        rebuildMenu()
    }

    private func observeAccounts() {
        withObservationTracking {
            _ = storageService.accounts
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
            let key = acc.issuer.isEmpty ? acc.name : acc.issuer
            dict[key, default: []].append(acc)
        }
        return dict.keys.sorted().map { ($0, dict[$0]!) }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environment(storageService)
            )
            let toolbar = NSToolbar(identifier: "settings")
            toolbar.displayMode = .iconOnly

            let window = NSWindow(contentViewController: hosting)
            window.title = "qr2fa"
            window.titleVisibility = .hidden
            window.styleMask = [.titled, .closable, .resizable,
                                .unifiedTitleAndToolbar, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.toolbar = toolbar
            window.setContentSize(NSSize(width: 960, height: 580))
            window.minSize = NSSize(width: 760, height: 440)
            window.center()
            window.delegate = self
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func noOp() {}
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
        NSApp.setActivationPolicy(.accessory)
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
