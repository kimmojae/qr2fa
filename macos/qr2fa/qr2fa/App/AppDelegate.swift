import AppKit
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let storageService = StorageService()
    private var statusItem: NSStatusItem!
    private var submenuDelegates: [SubMenuDelegate] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do { try storageService.load() } catch {
            NSLog("qr2fa: load failed: \(error)")
        }
        setupStatusItem()
        observeAccounts()
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
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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

    @objc private func noOp() {}
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
