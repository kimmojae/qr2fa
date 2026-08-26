import AppKit

/// 메뉴바 서브메뉴 한 줄의 가로 배치 규칙. 그리기와 분리해 두어 테스트에서 검증한다.
enum AccountMenuItemLayout {
    static let itemW: CGFloat = 300
    static let itemH: CGFloat = 24
    static let tagH: CGFloat = 14
    /// 짧은 태그("dev")가 쪼그라들어 보이지 않도록 하는 하한.
    static let tagMinW: CGFloat = 28
    /// 긴 태그가 이름 칼럼을 통째로 먹지 않도록 하는 상한.
    static let tagMaxW: CGFloat = 84
    static let tagHPad: CGFloat = 5
    static let tagGap: CGFloat = 6
    static let codeW: CGFloat = 60
    static let lPad: CGFloat = 16
    static let rPad: CGFloat = 14

    static let tagFont = NSFont.systemFont(ofSize: 9, weight: .semibold)

    static func textWidth(for tag: String) -> CGFloat {
        ceil((tag.lowercased() as NSString).size(withAttributes: [.font: tagFont]).width)
    }

    /// 배지는 태그 텍스트에 맞춰 넓어지되 하한/상한 사이에 머문다.
    static func badgeWidth(for tag: String) -> CGFloat {
        min(max(tagMinW, textWidth(for: tag) + tagHPad * 2), tagMaxW)
    }

    /// 이름이 그려지기 시작하는 x. 태그가 없으면 왼쪽 여백에서 바로 시작한다.
    static func nameX(badgeWidth: CGFloat?) -> CGFloat {
        guard let badgeWidth else { return lPad }
        return lPad + badgeWidth + tagGap
    }
}

final class AccountMenuItemView: NSView {
    private typealias L = AccountMenuItemLayout

    private let account: Account
    private var code: String = "------"
    private var remaining: Int = 30
    private var highlighted = false
    private var showCopied = false

    init(account: Account) {
        self.account = account
        super.init(frame: NSRect(x: 0, y: 0, width: L.itemW, height: L.itemH))
        updateCode()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: L.itemH)
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

        var badgeW: CGFloat?

        // Tag badge
        if !account.tag.isEmpty {
            let c = tagNSColor
            let bg: NSColor = highlighted ? .white.withAlphaComponent(0.2) : c.withAlphaComponent(0.15)
            let fg: NSColor = highlighted ? .white : c
            let bw = L.badgeWidth(for: account.tag)
            badgeW = bw
            let rect = NSRect(x: L.lPad, y: cy - L.tagH / 2, width: bw, height: L.tagH)
            bg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()

            // 상한에 걸린 태그는 배지 안에서 말줄임 처리한다.
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: L.tagFont,
                .foregroundColor: fg,
                .paragraphStyle: para
            ]
            let tag = account.tag.lowercased() as NSString
            let lineH = tag.size(withAttributes: attrs).height
            let textRect = NSRect(x: rect.minX + L.tagHPad,
                                  y: rect.midY - lineH / 2 + 0.5,
                                  width: rect.width - L.tagHPad * 2,
                                  height: lineH)
            tag.draw(with: textRect,
                     options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                     attributes: attrs,
                     context: nil)
        }

        // Geometry
        let x = L.nameX(badgeWidth: badgeW)
        let cX = w - L.rPad - L.codeW

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
            codeColor = .systemOrange
        } else {
            codeColor = textColor
        }
        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: codeColor
        ]
        let codeSz = codeStr.size(withAttributes: codeAttrs)
        codeStr.draw(at: NSPoint(x: cX + L.codeW - codeSz.width, y: cy - 7), withAttributes: codeAttrs)

    }

    /// 설정 창의 TagBadgeView와 같은 색을 쓴다. 태그별 프리셋 색은 없다.
    var tagNSColor: NSColor { TagPalette.nsColor }

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
