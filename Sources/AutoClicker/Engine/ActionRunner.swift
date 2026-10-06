import Foundation

protocol Clock {
    func now() -> Date
    func sleep(milliseconds: Int) async
}

struct SystemClock: Clock {
    func now() -> Date { Date() }

    func sleep(milliseconds: Int) async {
        let clamped = max(0, milliseconds)
        if clamped == 0 { return }
        try? await Task.sleep(nanoseconds: UInt64(clamped) * 1_000_000)
    }
}

final class ActionRunner {
    private let poster: InputPosting
    private let clock: Clock
    private var task: Task<Void, Never>?

    private(set) var isRunning = false

    init(poster: InputPosting, clock: Clock = SystemClock()) {
        self.poster = poster
        self.clock = clock
    }

    func start(settings: AppSettings, onFinished: @escaping @MainActor () -> Void) {
        stop()
        isRunning = true
        let snapshot = settings
        task = Task { [weak self] in
            guard let self else { return }
            await self.run(settings: snapshot)
            await MainActor.run {
                self.isRunning = false
                onFinished()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func run(settings: AppSettings) async {
        switch settings.mode {
        case .clickHere, .clickPoint, .key:
            await runIntervalMode(settings: settings)
        case .macro:
            await runMacro(settings: settings)
        }
    }

    private func runIntervalMode(settings: AppSettings) async {
        let limit = settings.repeatMode == .count ? settings.repeatCount : Int.max
        var performed = 0

        while !Task.isCancelled && performed < limit {
            performTick(settings: settings)
            performed += 1
            if performed >= limit || Task.isCancelled { break }
            await clock.sleep(milliseconds: settings.intervalMilliseconds)
        }
    }

    private func performTick(settings: AppSettings) {
        switch settings.mode {
        case .clickHere:
            poster.click(at: poster.currentMouseLocation(), button: settings.mouseButton)
        case .clickPoint:
            poster.click(at: settings.clickPoint.cgPoint, button: settings.mouseButton)
        case .key:
            guard !settings.keyChord.isEmpty else { return }
            poster.pressKey(settings.keyChord)
        case .macro:
            break
        }
    }

    private func runMacro(settings: AppSettings) async {
        guard !settings.macroSteps.isEmpty else { return }
        let limit = settings.repeatMode == .count ? settings.repeatCount : Int.max
        var loops = 0

        while !Task.isCancelled && loops < limit {
            for step in settings.macroSteps {
                if Task.isCancelled { return }
                await performMacroStep(step)
            }
            loops += 1
            if loops < limit, !Task.isCancelled {
                await clock.sleep(milliseconds: settings.macroLoopIntervalMilliseconds)
            }
        }
    }

    private func performMacroStep(_ step: MacroStep) async {
        switch step.kind {
        case .click:
            if let point = step.point {
                poster.click(at: point.cgPoint, button: step.mouseButton)
            }
            await clock.sleep(milliseconds: step.intervalMilliseconds)
        case .key:
            if let key = step.key, !key.isEmpty {
                poster.pressKey(key)
            }
            await clock.sleep(milliseconds: step.intervalMilliseconds)
        case .wait:
            await clock.sleep(milliseconds: step.waitMilliseconds)
        }
    }
}
