import AppKit
import Combine
import Foundation

final class ClickThroughPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class RunOverlayCard: NSView {
    private let currentField = NSTextField(labelWithString: " ")
    private let nextField = NSTextField(labelWithString: " ")
    private let timeField = NSTextField(labelWithString: " ")
    private let track = NSView()
    private let fill = NSView()
    private var cue: RunCue?
    private var fraction: CGFloat = 0
    private var timer: Timer?

    override var isOpaque: Bool { false }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 212, height: 86))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor
        layer?.borderWidth = 1

        configure(currentField, size: 11, weight: .semibold, alpha: 1)
        configure(nextField, size: 10, weight: .regular, alpha: 0.72)
        configure(timeField, size: 10, weight: .regular, alpha: 0.72)
        timeField.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        track.layer?.cornerRadius = 2
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 2

        addSubview(currentField)
        addSubview(nextField)
        addSubview(track)
        track.addSubview(fill)
        addSubview(timeField)
        applyAccent(.blue)
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    func update(cue: RunCue?, accent: OverlayAccent) {
        self.cue = cue
        applyAccent(accent)
        render()
        if cue?.waitMilliseconds ?? 0 > 0 {
            startTimer()
        } else {
            stopTimer()
        }
    }

    func setActive(_ active: Bool) {
        if active, cue?.waitMilliseconds ?? 0 > 0 {
            startTimer()
        } else if !active {
            stopTimer()
        }
    }

    private func applyAccent(_ accent: OverlayAccent) {
        let color = Self.color(accent)
        layer?.borderColor = color.withAlphaComponent(0.7).cgColor
        fill.layer?.backgroundColor = color.cgColor
    }

    private func render() {
        if let cue {
            currentField.stringValue = OverlayReadout.currentLine(
                label: cue.currentLabel,
                actionIndex: cue.actionIndex
            )
            nextField.stringValue = "Next  \(cue.nextLabel)"
            timeField.stringValue = OverlayReadout.countdown(
                waitMilliseconds: cue.waitMilliseconds,
                startedAt: cue.startedAt,
                at: Date()
            )
            fraction = CGFloat(
                OverlayReadout.fraction(
                    waitMilliseconds: cue.waitMilliseconds,
                    startedAt: cue.startedAt,
                    at: Date()
                )
            )
            track.isHidden = cue.waitMilliseconds <= 0
        } else {
            currentField.stringValue = "Starting…"
            nextField.stringValue = " "
            timeField.stringValue = " "
            fraction = 0
            track.isHidden = true
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        currentField.frame = NSRect(x: 10, y: bounds.height - 26, width: width - 20, height: 16)
        nextField.frame = NSRect(x: 10, y: bounds.height - 44, width: width - 20, height: 14)
        track.frame = NSRect(x: 10, y: bounds.height - 54, width: width - 20, height: 4)
        let fillWidth = max(0, track.bounds.width * min(1, fraction))
        fill.frame = NSRect(x: 0, y: 0, width: fillWidth, height: track.bounds.height)
        timeField.frame = NSRect(x: 10, y: 8, width: width - 20, height: 14)
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.render()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func configure(_ field: NSTextField, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = NSColor.white.withAlphaComponent(alpha)
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.drawsBackground = false
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
    }

    private static func color(_ accent: OverlayAccent) -> NSColor {
        switch accent {
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .orange: return .systemOrange
        case .red: return .systemRed
        case .purple: return .systemPurple
        }
    }
}

@MainActor
final class RunOverlayController {
    private weak var model: AppModel?
    private var panel: ClickThroughPanel?
    private var card: RunOverlayCard?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var anchoredScreen: NSScreen?
    private var displayedCue: RunCue?
    private var overlaySettings: OverlaySettings = .default
    private var lastCorner: OverlayCorner?
    private var lastVisible = false
    private var wasRunning = false

    func bind(to model: AppModel) {
        self.model = model
        cancellables.removeAll()
        removeObservers()

        model.runCueHandler = { [weak self] cue in
            self?.ingest(cue)
        }

        model.$isRunning
            .sink { [weak self] isRunning in
                guard let self else { return }
                if isRunning, !self.wasRunning {
                    self.displayedCue = nil
                    self.anchoredScreen = Self.screenContainingPointer()
                } else if !isRunning {
                    self.displayedCue = nil
                    self.anchoredScreen = nil
                }
                self.wasRunning = isRunning
                self.refreshCard()
                self.updateVisibility()
            }
            .store(in: &cancellables)

        model.$settings
            .map(\.overlay)
            .removeDuplicates()
            .sink { [weak self] overlay in
                guard let self else { return }
                let cornerChanged = self.lastCorner != overlay.corner
                self.overlaySettings = overlay
                self.refreshCard()
                self.updateVisibility()
                if cornerChanged || self.panel?.isVisible == true {
                    self.repositionIfNeeded(force: cornerChanged)
                }
            }
            .store(in: &cancellables)

        ensurePanel()
        overlaySettings = model.settings.overlay
        displayedCue = model.runCue
        wasRunning = model.isRunning
        refreshCard()
        updateVisibility()
        observeLifetime()
    }

    func shutdown() {
        model?.runCueHandler = nil
        cancellables.removeAll()
        removeObservers()
        card?.setActive(false)
        panel?.orderOut(nil)
        panel = nil
        card = nil
        model = nil
        anchoredScreen = nil
        displayedCue = nil
    }

    private func ingest(_ cue: RunCue?) {
        if let cue {
            displayedCue = cue
        } else if model?.isRunning != true {
            displayedCue = nil
        }
        refreshCard()
        updateVisibility()
        if lastVisible {
            panel?.orderFrontRegardless()
            panel?.displayIfNeeded()
        }
    }

    private func refreshCard() {
        card?.update(cue: displayedCue, accent: overlaySettings.accent)
        panel?.alphaValue = CGFloat(overlaySettings.opacity)
    }

    private func updateVisibility() {
        guard let model else {
            hide()
            return
        }
        let shouldShow = model.isRunning && model.settings.overlay.isEnabled
        if shouldShow {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        let panel = ensurePanel()
        refreshCard()
        repositionIfNeeded(force: !lastVisible)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        card?.setActive(true)
        lastVisible = true
    }

    private func hide() {
        card?.setActive(false)
        panel?.orderOut(nil)
        lastVisible = false
    }

    private func orderFrontIfNeeded() {
        guard lastVisible, let panel else { return }
        panel.orderFrontRegardless()
    }

    @discardableResult
    private func ensurePanel() -> ClickThroughPanel {
        if let panel {
            return panel
        }

        let card = RunOverlayCard()
        let panel = ClickThroughPanel(
            contentRect: NSRect(x: 0, y: 0, width: 212, height: 86),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = card

        self.card = card
        self.panel = panel
        return panel
    }

    private func observeLifetime() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.orderFrontIfNeeded()
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.orderFrontIfNeeded()
                }
            }
        )
    }

    private func removeObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func repositionIfNeeded(force: Bool) {
        guard let panel else { return }
        let corner = overlaySettings.corner
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
