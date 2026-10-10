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
    private var onCue: ((RunCue?) -> Void)?

    private(set) var isRunning = false

    init(poster: InputPosting, clock: Clock = SystemClock()) {
        self.poster = poster
        self.clock = clock
    }

    func start(
        settings: AppSettings,
        onCue: ((RunCue?) -> Void)? = nil,
        onFinished: @escaping @MainActor () -> Void
    ) {
        stop()
        isRunning = true
        self.onCue = onCue
        let snapshot = settings
        task = Task { [weak self] in
            guard let self else { return }
            await self.run(settings: snapshot)
            let finishedCue = self.onCue
            self.onCue = nil
            await MainActor.run {
                finishedCue?(nil)
                self.isRunning = false
                onFinished()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        let clear = onCue
        onCue = nil
        Task { @MainActor in
            clear?(nil)
        }
    }

    private func emit(_ cue: RunCue?) async {
        let callback = onCue
        await MainActor.run {
            callback?(cue)
        }
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
        let label = RunLabels.intervalAction(settings)

        while !Task.isCancelled && performed < limit {
            performTick(settings: settings)
            performed += 1
            if performed >= limit || Task.isCancelled {
                if !Task.isCancelled {
                    await emit(.finished(current: label, startedAt: clock.now()))
                }
                break
            }
            await emit(
                .waiting(
                    current: label,
                    next: label,
                    waitMilliseconds: settings.intervalMilliseconds,
                    startedAt: clock.now()
                )
            )
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
        let steps = settings.macroSteps

        while !Task.isCancelled && loops < limit {
            for index in steps.indices {
                if Task.isCancelled { return }
                let step = steps[index]
                let current = RunLabels.macroStep(step)
                let isLastStep = index == steps.count - 1
                let isLastLoop = loops + 1 >= limit

                switch step.kind {
                case .click:
                    if let point = step.point {
                        poster.click(at: point.cgPoint, button: step.mouseButton)
                    }
                    if isLastStep, isLastLoop {
                        await emit(.finished(current: current, startedAt: clock.now()))
                    } else {
                        let next = nextMacroLabel(
                            steps: steps,
                            afterIndex: index,
                            willLoop: !isLastLoop,
                            loopInterval: settings.macroLoopIntervalMilliseconds
                        )
                        await emit(
                            .waiting(
                                current: current,
                                next: next,
                                waitMilliseconds: step.intervalMilliseconds,
                                startedAt: clock.now()
                            )
                        )
                    }
                    await clock.sleep(milliseconds: step.intervalMilliseconds)
                case .key:
                    if let key = step.key, !key.isEmpty {
                        poster.pressKey(key)
                    }
                    if isLastStep, isLastLoop {
                        await emit(.finished(current: current, startedAt: clock.now()))
                    } else {
                        let next = nextMacroLabel(
                            steps: steps,
                            afterIndex: index,
                            willLoop: !isLastLoop,
                            loopInterval: settings.macroLoopIntervalMilliseconds
                        )
                        await emit(
                            .waiting(
                                current: current,
                                next: next,
                                waitMilliseconds: step.intervalMilliseconds,
                                startedAt: clock.now()
                            )
                        )
                    }
                    await clock.sleep(milliseconds: step.intervalMilliseconds)
                case .wait:
                    if isLastStep, isLastLoop {
                        await emit(.finished(current: current, startedAt: clock.now()))
                    } else {
                        let next = nextMacroLabel(
                            steps: steps,
                            afterIndex: index,
                            willLoop: !isLastLoop,
                            loopInterval: settings.macroLoopIntervalMilliseconds
                        )
                        await emit(
                            .waiting(
                                current: current,
                                next: next,
                                waitMilliseconds: step.waitMilliseconds,
                                startedAt: clock.now()
                            )
                        )
                    }
                    await clock.sleep(milliseconds: step.waitMilliseconds)
                }
            }
            loops += 1
            if loops < limit, !Task.isCancelled {
                let first = RunLabels.macroStep(steps[0])
                await emit(
                    .waiting(
                        current: "Loop pause",
                        next: first,
                        waitMilliseconds: settings.macroLoopIntervalMilliseconds,
                        startedAt: clock.now()
                    )
                )
                await clock.sleep(milliseconds: settings.macroLoopIntervalMilliseconds)
            }
        }
    }

    private func nextMacroLabel(
        steps: [MacroStep],
        afterIndex: Int,
        willLoop: Bool,
        loopInterval: Int
    ) -> String {
        let nextIndex = afterIndex + 1
        if nextIndex < steps.count {
            return RunLabels.macroStep(steps[nextIndex])
        }
        if willLoop {
            return loopInterval > 0 ? "Loop pause" : RunLabels.macroStep(steps[0])
        }
        return "Done"
    }
}
