import AppKit
import SwiftUI

enum PanelWindowAnchor {
    /// Pins a panel to the top of its screen. Tall MenuBarExtra windows are
    /// otherwise recentered mid-desktop by the system.
    static func pinNearTop(_ window: NSWindow?) {
        guard let window else { return }
        apply(to: window)
    }

    static func apply(to window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        guard frame.width > 1, frame.height > 1 else { return }

        let margin: CGFloat = 10
        let maxHeight = min(560, visible.height * 0.62)
        if frame.height > maxHeight {
            frame.size.height = maxHeight
        }

        let targetY = visible.maxY - frame.height - margin
        let minX = visible.minX + margin
        let maxX = max(minX, visible.maxX - frame.width - margin)
        frame.origin.x = min(max(minX, frame.origin.x), maxX)
        frame.origin.y = min(max(visible.minY + margin, targetY), visible.maxY - frame.height - margin)

        if abs(frame.origin.x - window.frame.origin.x) > 0.5
            || abs(frame.origin.y - window.frame.origin.y) > 0.5
            || abs(frame.size.height - window.frame.size.height) > 0.5
        {
            window.setFrame(frame, display: true)
        }
    }
}

/// Observes the hosting window and keeps it pinned under the menu bar.
struct PinHostWindowToTop: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = context.coordinator.view
        context.coordinator.schedulePin()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.schedulePin()
    }

    final class Coordinator {
        let view = ObserverView()
        private var pending = false

        init() {
            view.onWindow = { [weak self] in
                self?.schedulePin()
            }
        }

        func schedulePin() {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pending = false
                PanelWindowAnchor.pinNearTop(self.view.window)
            }
            // MenuBarExtra finishes sizing after the first layout pass.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                PanelWindowAnchor.pinNearTop(self?.view.window)
            }
        }
    }

    final class ObserverView: NSView {
        var onWindow: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?()
        }

        override func layout() {
            super.layout()
            onWindow?()
        }
    }
}
