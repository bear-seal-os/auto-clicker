import AppKit
import Combine
import SwiftUI

@MainActor
final class RunOverlayState: ObservableObject {
    @Published var cue: RunCue?
    @Published var settings: OverlaySettings = .default
    @Published var isVisible = false
}

struct RunOverlayView: View {
    @ObservedObject var state: RunOverlayState

    var body: some View {
        Group {
            if let cue = state.cue {
                content(cue: cue)
            } else {
                Color.clear
            }
        }
        .frame(width: 212, height: 86)
        .opacity(state.settings.opacity)
    }

    @ViewBuilder
    private func content(cue: RunCue) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { context in
            let fraction = progressFraction(cue: cue, at: context.date)
            let secondsLeft = remainingWholeSeconds(cue: cue, at: context.date)
            VStack(alignment: .leading, spacing: 6) {
                Text(cue.currentLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Text("Next")
                        .foregroundStyle(.secondary)
                    Text(cue.nextLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption2)

                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(accentColor)
                    .opacity(cue.waitMilliseconds > 0 ? 1 : 0)
                    .animation(nil, value: fraction)
                    .animation(nil, value: cue.startedAt)

                Text(cue.waitMilliseconds > 0 ? "\(secondsLeft)s" : " ")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.identity)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(accentColor.opacity(0.45), lineWidth: 1)
            )
        }
    }

    private var accentColor: Color {
        switch state.settings.accent {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        }
    }

    private func progressFraction(cue: RunCue, at date: Date) -> Double {
        guard cue.waitMilliseconds > 0 else { return 1 }
        let duration = Double(cue.waitMilliseconds) / 1000
        let elapsed = max(0, date.timeIntervalSince(cue.startedAt))
        return min(1, max(0, elapsed / duration))
    }

    private func remainingWholeSeconds(cue: RunCue, at date: Date) -> Int {
        guard cue.waitMilliseconds > 0 else { return 0 }
        let duration = Double(cue.waitMilliseconds) / 1000
        let remaining = max(0, duration - date.timeIntervalSince(cue.startedAt))
        if remaining <= 0 { return 0 }
        return max(1, Int(ceil(remaining)))
    }
}

@MainActor
final class RunOverlayController {
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<RunOverlayView>?
    private let state = RunOverlayState()
    private var cancellables = Set<AnyCancellable>()
    private var anchoredScreen: NSScreen?
    private var lastCorner: OverlayCorner?
    private var lastVisible = false

    func bind(to model: AppModel) {
        self.model = model
        cancellables.removeAll()

        model.$runCue
            .receive(on: RunLoop.main)
            .sink { [weak self] cue in
                self?.state.cue = cue
                self?.updateVisibility()
            }
            .store(in: &cancellables)

        model.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] isRunning in
                guard let self else { return }
                if isRunning {
                    self.anchoredScreen = Self.screenContainingPointer()
                } else {
                    self.anchoredScreen = nil
                }
                self.updateVisibility()
            }
            .store(in: &cancellables)

        model.$settings
            .map(\.overlay)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] overlay in
                guard let self else { return }
                let cornerChanged = self.lastCorner != overlay.corner
                self.state.settings = overlay
                self.updateVisibility()
                if cornerChanged || self.panel?.isVisible == true {
                    self.repositionIfNeeded(force: cornerChanged)
                }
            }
            .store(in: &cancellables)

        ensurePanel()
        state.settings = model.settings.overlay
        state.cue = model.runCue
        updateVisibility()
    }

    func shutdown() {
        cancellables.removeAll()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        model = nil
        anchoredScreen = nil
    }

    private func updateVisibility() {
        guard let model else {
            hide()
            return
        }
        let shouldShow = model.isRunning && model.settings.overlay.isEnabled && model.runCue != nil
        state.isVisible = shouldShow
        if shouldShow {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        let panel = ensurePanel()
        repositionIfNeeded(force: !lastVisible)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        lastVisible = true
    }

    private func hide() {
        panel?.orderOut(nil)
        lastVisible = false
    }

    @discardableResult
    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let root = RunOverlayView(state: state)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 212, height: 86)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 212, height: 86),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = host

        self.hostingView = host
        self.panel = panel
        return panel
    }

    private func repositionIfNeeded(force: Bool) {
        guard let panel else { return }
        let corner = state.settings.corner
        if !force, lastCorner == corner, panel.isVisible { return }
        lastCorner = corner

        let screen = anchoredScreen ?? Self.screenContainingPointer() ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = NSSize(width: 212, height: 86)
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

    private static func screenContainingPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
    }
}
