import AppKit
import SwiftUI

enum PanelWindowAnchor {
    /// Moves a panel to the top of its screen without changing its size.
    /// (Resizing here fought SwiftUI layout and blanked the MenuBarExtra content.)
    static func pinNearTop(_ window: NSWindow?) {
        guard let window else { return }
        apply(to: window)
    }

    static func apply(to window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = window.frame
        guard frame.width > 1, frame.height > 1 else { return }

        let margin: CGFloat = 10
        let targetY = visible.maxY - frame.height - margin
        let minX = visible.minX + margin
        let maxX = max(minX, visible.maxX - frame.width - margin)
        let origin = NSPoint(
            x: min(max(minX, frame.origin.x), maxX),
            y: min(max(visible.minY + margin, targetY), visible.maxY - frame.height - margin)
        )

        if abs(origin.x - frame.origin.x) > 0.5 || abs(origin.y - frame.origin.y) > 0.5 {
            window.setFrameOrigin(origin)
        }
    }
}

/// Pins the hosting window under the menu bar after it appears.
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
        // Avoid re-pinning on every SwiftUI refresh; appear/move is enough.
    }

    final class Coordinator {
        let view = ObserverView()

        init() {
            view.onWindow = { [weak self] in
                self?.schedulePin()
            }
        }

        func schedulePin() {
            DispatchQueue.main.async { [weak self] in
                PanelWindowAnchor.pinNearTop(self?.view.window)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
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
    }
}
