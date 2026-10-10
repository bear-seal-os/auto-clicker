import AppKit
import Combine
import SwiftUI

struct RunOverlayView: View {
    let cue: RunCue
    let overlay: OverlaySettings

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let remaining = remainingMilliseconds(at: context.date)
            VStack(alignment: .leading, spacing: 6) {
                Text(cue.currentLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("Next")
                        .foregroundStyle(.secondary)
                    Text(cue.nextLabel)
                        .lineLimit(1)
                }
                .font(.caption2)
                if cue.waitMilliseconds > 0 {
                    ProgressView(value: progress(remaining: remaining))
                        .tint(accentColor)
                    Text(formatMilliseconds(remaining))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(width: 200, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(accentColor.opacity(0.45), lineWidth: 1)
            )
            .opacity(overlay.opacity)
        }
    }

    private var accentColor: Color {
        switch overlay.accent {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        }
    }

    private func remainingMilliseconds(at date: Date) -> Int {
        guard cue.waitMilliseconds > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(cue.startedAt) * 1000
        return max(0, cue.waitMilliseconds - Int(elapsed.rounded()))
    }

    private func progress(remaining: Int) -> Double {
        guard cue.waitMilliseconds > 0 else { return 1 }
        return 1 - (Double(remaining) / Double(cue.waitMilliseconds))
    }

    private func formatMilliseconds(_ value: Int) -> String {
        if value >= 1000 {
            return String(format: "%.1fs", Double(value) / 1000)
        }
        return "\(value)ms"
    }
}

@MainActor
final class RunOverlayController {
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?

    func bind(to model: AppModel) {
        self.model = model
        cancellable = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Defer until after Published properties update.
                DispatchQueue.main.async {
                    self?.refresh()
                }
            }
        refresh()
    }

    func shutdown() {
        cancellable?.cancel()
        cancellable = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    private func refresh() {
        guard let model else {
            panel?.orderOut(nil)
            return
        }
        let shouldShow = model.isRunning && model.settings.overlay.isEnabled && model.runCue != nil
        guard shouldShow, let cue = model.runCue else {
            panel?.orderOut(nil)
            return
        }

        let root = RunOverlayView(cue: cue, overlay: model.settings.overlay)
        let host = NSHostingView(rootView: root)
        let fitting = host.fittingSize
        let size = NSSize(
            width: max(fitting.width, 200),
            height: max(fitting.height, 72)
        )
        host.frame = NSRect(origin: .zero, size: size)

        let panel = ensurePanel()
        panel.contentView = host
        position(panel, corner: model.settings.overlay.corner, size: size)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, corner: OverlayCorner, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 12
        let origin: NSPoint
        switch corner {
        case .topLeft:
            origin = NSPoint(x: visible.minX + margin, y: visible.maxY - size.height - margin)
        case .topRight:
            origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin)
        case .bottomLeft:
            origin = NSPoint(x: visible.minX + margin, y: visible.minY + margin)
        case .bottomRight:
            origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.minY + margin)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
