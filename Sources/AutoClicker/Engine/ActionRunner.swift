import Darwin
import Foundation

protocol Clock {
    func now() -> Date
    func sleep(milliseconds: Int) async
}

enum IntervalTiming {
    static func remainingMilliseconds(interval: Int, elapsed: TimeInterval) -> Int {
        let elapsedMs = Int((elapsed * 1000).rounded())
        return max(0, interval - max(0, elapsedMs))
    }
}

enum PreciseWait {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func sleep(milliseconds: Int) async {
        var left = max(0, milliseconds)
        while left > 0 {
            if Task.isCancelled { return }
            let chunk = left > 100 ? 100 : left
            await block(milliseconds: chunk)
            left -= chunk
        }
    }

    private static func block(milliseconds: Int) async {
        let ticks = UInt64(milliseconds) * 1_000_000 * UInt64(timebase.denom) / UInt64(timebase.numer)
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                mach_wait_until(mach_absolute_time() &+ ticks)
                continuation.resume()
            }
        }
    }
}

struct SystemClock: Clock {
    func now() -> Date { Date() }

    func sleep(milliseconds: Int) async {
        await PreciseWait.sleep(milliseconds: milliseconds)
    }
}

final class ActionRunner {
    private let poster: InputPosting
    private let clock: Clock
    private var task: Task<Void, Never>?
    private var onCue: (@MainActor (RunCue?) -> Void)?
    private var activity: NSObjectProtocol?

    private(set) var isRunning = false

    init(poster: InputPosting, clock: Clock = SystemClock()) {
        self.poster = poster
        self.clock = clock
    }

    func start(
        settings: AppSettings,
        onCue: (@MainActor (RunCue?) -> Void)? = nil,
        onFinished: @escaping @MainActor () -> Void
    ) {
        stop()
        isRunning = true
        self.onCue = onCue
        let snapshot = settings
        beginActivity()
        task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.run(settings: snapshot)
            let finishedCue = self.onCue
            self.onCue = nil
            await MainActor.run {
                finishedCue?(nil)
                self.isRunning = false
                onFinished()
            }
            self.endActivity()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        let clear = onCue
        onCue = nil
        endActivity()
        Task { @MainActor in
            clear?(nil)
        }
    }

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Repeating clicks and keys"
        )
    }

    private func endActivity() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    private func pause(for milliseconds: Int, since started: Date) async {
        let elapsed = clock.now().timeIntervalSince(started)
        let remaining = IntervalTiming.remainingMilliseconds(interval: milliseconds, elapsed: elapsed)
        guard remaining > 0 else { return }
        await clock.sleep(milliseconds: remaining)
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
            let started = clock.now()
            let index = performed + 1
            if index >= limit {
                performTick(settings: settings)
                performed += 1
                if !Task.isCancelled {
                    await emit(.finished(current: label, actionIndex: performed, startedAt: started))
                }
                break
            }
            await emit(
                .waiting(
                    current: label,
                    next: label,
                    waitMilliseconds: settings.intervalMilliseconds,
                    actionIndex: index,
                    startedAt: started
                )
            )
            if Task.isCancelled { return }
            performTick(settings: settings)
            performed += 1
            await pause(for: settings.intervalMilliseconds, since: started)
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
        var actionIndex = 0
        let steps = settings.macroSteps

        while !Task.isCancelled && loops < limit {
            for index in steps.indices {
                if Task.isCancelled { return }
                let step = steps[index]
                let current = RunLabels.macroStep(step)
                let isLastStep = index == steps.count - 1
                let isLastLoop = loops + 1 >= limit
                let wait = step.kind == .wait ? step.waitMilliseconds : step.intervalMilliseconds
                actionIndex += 1
                let started = clock.now()

                if isLastStep, isLastLoop {
                    performMacroStep(step)
                    await emit(.finished(current: current, actionIndex: actionIndex, startedAt: started))
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
                            waitMilliseconds: wait,
                            actionIndex: actionIndex,
                            startedAt: started
                        )
                    )
                    if Task.isCancelled { return }
                    performMacroStep(step)
                }
                await pause(for: wait, since: started)
            }
            loops += 1
            if loops < limit, !Task.isCancelled {
                actionIndex += 1
                let first = RunLabels.macroStep(steps[0])
                let started = clock.now()
                await emit(
                    .waiting(
                        current: "Loop pause",
                        next: first,
                        waitMilliseconds: settings.macroLoopIntervalMilliseconds,
                        actionIndex: actionIndex,
                        startedAt: started
                    )
                )
                await pause(for: settings.macroLoopIntervalMilliseconds, since: started)
            }
        }
    }

    private func performMacroStep(_ step: MacroStep) {
        switch step.kind {
        case .click:
            if let point = step.point {
                poster.click(at: point.cgPoint, button: step.mouseButton)
            }
        case .key:
            if let key = step.key, !key.isEmpty {
                poster.pressKey(key)
            }
        case .wait:
            break
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
