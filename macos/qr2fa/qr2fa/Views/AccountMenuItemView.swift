import AppKit

final class AccountMenuItemView: NSView {
    private let account: Account
    private var code: String = "------"
    private var remaining: Int = 30
    private var highlighted = false
    private var showCopied = false

    private static let itemH: CGFloat = 24
    private static let tagW: CGFloat = 28
    private static let tagH: CGFloat = 14
    private static let codeW: CGFloat = 60
    private static let lPad: CGFloat = 16
    private static let rPad: CGFloat = 14

    init(account: Account) {
        self.account = account
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: Self.itemH))
        updateCode()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.itemH)
    }

    // MARK: - State (called by SubMenuDelegate)

    func setHighlighted(_ hl: Bool) {
        guard highlighted != hl else { return }
        highlighted = hl
        needsDisplay = true
    }

    func updateCode() {
        let raw = (try? TOTPGenerator.generate(account: account)) ?? "------"
        let rem = TOTPGenerator.remainingSeconds(period: account.period)
        code = raw
        remaining = rem
        needsDisplay = true
    }

    // MARK: - Draw everything inline — no subview layer conflicts

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height, cy = h / 2
        let textColor: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor

        if highlighted {
            NSColor.selectedMenuItemColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 2), xRadius: 6, yRadius: 6).fill()
        }

        var x = Self.lPad

        // Tag badge
        if !account.tag.isEmpty {
            let c = tagNSColor
            let bg: NSColor = highlighted ? .white.withAlphaComponent(0.2) : c.withAlphaComponent(0.15)
            let fg: NSColor = highlighted ? .white : c
            let rect = NSRect(x: x, y: cy - Self.tagH / 2, width: Self.tagW, height: Self.tagH)
            bg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            let tag = account.tag.lowercased() as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: fg
            ]
            let sz = tag.size(withAttributes: attrs)
            tag.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2 + 0.5),
                     withAttributes: attrs)
            x += Self.tagW + 6
        }

        // Geometry
        let cX = w - Self.rPad - Self.codeW

        // Name (truncated)
        let nameRect = NSRect(x: x, y: cy - 7, width: max(0, cX - x - 8), height: 14)
        (account.name as NSString).draw(
            with: nameRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: textColor],
            context: nil
        )

        // Code (right-aligned)
        let codeStr = (showCopied ? "Copied!" : TOTPGenerator.formattedCode(code)) as NSString
        let codeColor: NSColor
        if showCopied {
            codeColor = .systemGreen
        } else if !highlighted && remaining <= 5 {
            codeColor = .systemRed
        } else {
            codeColor = textColor
        }
        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: codeColor
        ]
        let codeSz = codeStr.size(withAttributes: codeAttrs)
        codeStr.draw(at: NSPoint(x: cX + Self.codeW - codeSz.width, y: cy - 7), withAttributes: codeAttrs)

    }

    private var tagNSColor: NSColor {
        switch account.tag.lowercased() {
        case "dev": return .systemBlue
        case "prod": return .systemOrange
        case "rnd": return .systemGreen
        case "all": return .systemPurple
        default: return .secondaryLabelColor
        }
    }

    // MARK: - Click → copy code

    override func mouseUp(with event: NSEvent) {
        guard let raw = try? TOTPGenerator.generate(account: account) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(raw, forType: .string)
        showCopied = true
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showCopied = false
            self?.needsDisplay = true
        }
    }
}
