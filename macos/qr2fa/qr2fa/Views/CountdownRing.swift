import AppKit
import SwiftUI

/// 코드가 바뀌기까지 남은 시간을 그리는 링. 설정 창의 목록 툴바와 상세의 인증 코드 줄이
/// 같은 것을 쓴다 — 한 화면에 둘이 같이 보이므로 규칙이 갈리면 바로 티가 난다.
///
/// **차오른다.** 줄어드는 게 아니라 0에서 한 바퀴를 채우고, 주기가 끝나면 값이 되돌아가면서
/// 링도 거꾸로 풀린다. 1초짜리 선형 애니메이션이 그 되돌림까지 이어 그려 줘서 툭 끊기지 않는다.
///
/// **5초가 남으면 주황.** 암호 앱은 끝까지 한 가지 색으로 가는데, 여기서는 지금 복사하면
/// 붙여 넣기도 전에 만료될 수 있다는 걸 색으로 알린다. 되돌아간 뒤에는 다시 초록이다 —
/// 새 코드는 급하지 않으니까.
///
/// 색이 바뀌는 방식은 **주황 호를 초록 호 위에 겹쳐 두고 투명도만 여닫는** 것이다. 획의
/// 색을 통째로 갈아 끼우면 두 색 사이가 섞이지 않고 툭 바뀌는데, 투명도는 무조건 섞인다.
///
/// 호가 차는 것과 색이 바뀌는 건 속도가 다르다 — 채움은 1초 선형(다음 틱까지 정확히
/// 이어져야 한다), 색은 조금 짧게 감속으로 끊어 줘야 "바뀌었다"가 읽힌다.
///
/// **그리는 건 SwiftUI가 아니라 Core Animation이다.** 매초 1초짜리 애니메이션을 거는
/// 링은 애니메이션이 한 번도 쉬지 않는다. SwiftUI로 그리면 그 매 프레임을 앱 프로세스가
/// 다시 계산해서, 계정 창을 띄워 두기만 해도 CPU를 20~30% 먹었다(같은 창에서 애니메이션만
/// 끄면 2% 아래). `CAShapeLayer`에 애니메이션을 넘기면 프레임은 렌더 서버가 그린다.
struct CountdownRing: View {
    static let expiringSeconds = 5

    let remaining: Int
    let period: Int
    var lineWidth: CGFloat = 3

    var body: some View {
        RingLayerView(fraction: CGFloat(period - remaining) / CGFloat(max(period, 1)),
                      expiring: remaining <= Self.expiringSeconds,
                      lineWidth: lineWidth)
    }
}

private struct RingLayerView: NSViewRepresentable {
    let fraction: CGFloat
    let expiring: Bool
    let lineWidth: CGFloat

    func makeNSView(context: Context) -> RingNSView { RingNSView() }

    func updateNSView(_ view: RingNSView, context: Context) {
        view.lineWidth = lineWidth
        // 패널을 다시 열 때처럼 바깥이 애니메이션을 끄라고 하면 그대로 따른다.
        view.update(fraction: fraction,
                    expiring: expiring,
                    animated: !context.transaction.disablesAnimations)
    }
}

private final class RingNSView: NSView {
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    private let warning = CAShapeLayer()
    /// 처음 그릴 때는 0에서 차오르는 애니메이션을 보여 주지 않는다.
    private var hasValue = false

    var lineWidth: CGFloat = 3 {
        didSet { if lineWidth != oldValue { needsLayout = true } }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        for shape in [track, fill, warning] {
            shape.fillColor = nil
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }
        track.lineCap = .butt
        fill.strokeEnd = 0
        warning.strokeEnd = 0
        warning.opacity = 0
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let radius = min(bounds.width, bounds.height) / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        // 12시에서 시작해 시계 방향으로 찬다(뒤집히지 않은 좌표계 기준).
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius,
                    startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [track, fill, warning] {
            shape.frame = bounds
            shape.path = path
            shape.lineWidth = lineWidth
        }
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for shape in [track, fill, warning] { shape.contentsScale = scale }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyColors()
    }

    /// 동적 색은 CGColor로 바꾸는 순간 고정되므로 외관이 바뀔 때마다 다시 푼다.
    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            track.strokeColor = NSColor.secondaryLabelColor.withAlphaComponent(0.25).cgColor
            fill.strokeColor = NSColor.systemGreen.cgColor
            warning.strokeColor = NSColor(Color.codeExpiring).cgColor
            CATransaction.commit()
        }
    }

    func update(fraction: CGFloat, expiring: Bool, animated: Bool) {
        let animate = animated && hasValue
        hasValue = true
        set(fill, "strokeEnd", to: fraction, duration: 1, timing: .linear, animated: animate)
        set(warning, "strokeEnd", to: fraction, duration: 1, timing: .linear, animated: animate)
        set(warning, "opacity", to: expiring ? 1 : 0, duration: 0.6, timing: .easeInEaseOut, animated: animate)
    }

    /// 지금 화면에 보이는 값에서 새 값까지 잇는다. 1초마다 새 값이 오므로 이전 애니메이션이
    /// 거의 끝난 자리에서 다음 것이 시작되고, 링은 끊김 없이 이어진다.
    private func set(_ shape: CAShapeLayer, _ keyPath: String, to value: CGFloat,
                     duration: CFTimeInterval, timing: CAMediaTimingFunctionName, animated: Bool) {
        let model = (shape.value(forKeyPath: keyPath) as? NSNumber).map { CGFloat($0.doubleValue) }
        guard model != value else { return }
        let shown = (shape.presentation()?.value(forKeyPath: keyPath) as? NSNumber).map { CGFloat($0.doubleValue) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.setValue(value, forKeyPath: keyPath)
        CATransaction.commit()
        shape.removeAnimation(forKey: keyPath)
        guard animated, let from = shown ?? model else { return }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        shape.add(animation, forKey: keyPath)
    }
}
