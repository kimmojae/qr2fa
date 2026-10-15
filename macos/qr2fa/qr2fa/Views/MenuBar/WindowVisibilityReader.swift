import AppKit
import SwiftUI

/// 이 뷰가 들어 있는 창이 지금 화면에 보이는지를 바인딩으로 알려 준다.
///
/// `MenuBarExtra(.window)`의 패널은 **닫혀도 뷰가 해체되지 않는다** — 창이 `orderOut`될
/// 뿐이라 `onDisappear`도 믿을 수 없다. 그 상태에서 1초 시계를 계속 읽으면 화면에 없는
/// 링이 매초 1초짜리 애니메이션을 새로 시작하고, 그게 끝없이 이어져 디스플레이 주사율로
/// 다시 그려진다(실측: 패널을 닫아 둔 채 CPU 40% 안팎). 창의 occlusion 상태는 AppKit이
/// 열고 닫을 때마다 확실히 알려 주는 신호다.
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = { visible in
            guard visible != isVisible else { return }
            isVisible = visible
        }
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onChange = { visible in
            guard visible != isVisible else { return }
            isVisible = visible
        }
    }

    final class ReaderView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in self?.report() }
            report()
        }

        private func report() {
            guard let window else { return }
            let visible = window.occlusionState.contains(.visible)
            // SwiftUI 갱신 도중에 상태를 바꾸지 않도록 한 박자 미룬다.
            DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
