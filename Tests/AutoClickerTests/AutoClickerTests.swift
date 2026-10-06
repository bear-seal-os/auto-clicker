import Foundation
@testable import AutoClicker
import XCTest

final class FakePoster: InputPosting {
    struct Click: Equatable {
        let point: CGPoint
        let button: MouseButton
    }

    var clicks: [Click] = []
    var keys: [KeyChord] = []
    var mouseLocation = CGPoint(x: 10, y: 20)

    func click(at point: CGPoint, button: MouseButton) {
        clicks.append(Click(point: point, button: button))
    }

    func pressKey(_ chord: KeyChord) {
        keys.append(chord)
    }

    func currentMouseLocation() -> CGPoint {
        mouseLocation
    }
}

final class ControllableClock: Clock {
    private(set) var sleepCalls: [Int] = []
    var sleepHandler: ((Int) async -> Void)?

    func now() -> Date { Date() }

    func sleep(milliseconds: Int) async {
        sleepCalls.append(milliseconds)
        if let sleepHandler {
            await sleepHandler(milliseconds)
        }
    }
}

final class SettingsTests: XCTestCase {
    func testClampRaisesIntervalToMinimum() {
        var settings = AppSettings.default
        settings.intervalMilliseconds = 1
        settings.repeatCount = 0
        settings.macroSteps = [.wait(-5)]
        settings.clamp()
        XCTAssertEqual(settings.intervalMilliseconds, AppSettings.minimumInterval)
        XCTAssertEqual(settings.repeatCount, 1)
        XCTAssertEqual(settings.macroSteps[0].waitMilliseconds, 0)
    }

    func testSettingsRoundTrip() throws {
        var settings = AppSettings.default
        settings.mode = .macro
        settings.intervalMilliseconds = 50
        settings.mouseButton = .right
        settings.repeatMode = .count
        settings.repeatCount = 3
        settings.clickPoint = ScreenPoint(x: 100, y: 200)
        settings.keyChord = KeyChord(keyCode: 0, modifiers: 0, displayName: "A")
        settings.macroSteps = [
            .click(ScreenPoint(x: 1, y: 2), button: .left),
            .key(KeyChord(keyCode: 49, modifiers: 0, displayName: "Space")),
            .wait(25)
        ]
        settings.toggleHotkey = KeyChord(keyCode: 8, modifiers: 262_144, displayName: "⌃C")

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testSettingsStorePersists() {
        let defaults = UserDefaults(suiteName: "AutoClickerTests.\(UUID().uuidString)")!
        var settings = AppSettings.default
        settings.mode = .key
        settings.intervalMilliseconds = 42
        SettingsStore.save(settings, defaults: defaults)
        let loaded = SettingsStore.load(defaults: defaults)
        XCTAssertEqual(loaded.mode, .key)
        XCTAssertEqual(loaded.intervalMilliseconds, 42)
    }
}

final class MacroStepTests: XCTestCase {
    func testMacroStepFactories() {
        let click = MacroStep.click(ScreenPoint(x: 5, y: 6), button: .right)
        XCTAssertEqual(click.kind, .click)
        XCTAssertEqual(click.point, ScreenPoint(x: 5, y: 6))
        XCTAssertEqual(click.mouseButton, .right)

        let key = MacroStep.key(KeyChord(keyCode: 1, modifiers: 0, displayName: "S"))
        XCTAssertEqual(key.kind, .key)
        XCTAssertEqual(key.key?.keyCode, 1)

        let wait = MacroStep.wait(123)
        XCTAssertEqual(wait.kind, .wait)
        XCTAssertEqual(wait.waitMilliseconds, 123)
    }

    func testMovePreservesOrderSemantics() {
        var steps = [
            MacroStep.wait(1),
            MacroStep.wait(2),
            MacroStep.wait(3)
        ]
        steps.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(steps.map(\.waitMilliseconds), [2, 3, 1])
    }
}

final class ActionRunnerTests: XCTestCase {
    func testClickHereUsesLiveMouseLocation() async {
        let poster = FakePoster()
        poster.mouseLocation = CGPoint(x: 33, y: 44)
        let clock = ControllableClock()
        let runner = ActionRunner(poster: poster, clock: clock)

        var settings = AppSettings.default
        settings.mode = .clickHere
        settings.repeatMode = .count
        settings.repeatCount = 2
        settings.intervalMilliseconds = 10
        settings.mouseButton = .left

        let finished = expectation(description: "finished")
        runner.start(settings: settings) {
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(poster.clicks.count, 2)
        XCTAssertEqual(poster.clicks[0].point, CGPoint(x: 33, y: 44))
        XCTAssertEqual(clock.sleepCalls, [10])
    }

    func testClickPointUsesSavedPoint() async {
        let poster = FakePoster()
        let clock = ControllableClock()
        let runner = ActionRunner(poster: poster, clock: clock)

        var settings = AppSettings.default
        settings.mode = .clickPoint
        settings.clickPoint = ScreenPoint(x: 90, y: 80)
        settings.repeatMode = .count
        settings.repeatCount = 1
        settings.mouseButton = .right

        let finished = expectation(description: "finished")
        runner.start(settings: settings) {
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(poster.clicks, [FakePoster.Click(point: CGPoint(x: 90, y: 80), button: .right)])
    }

    func testKeyModePressesChord() async {
        let poster = FakePoster()
        let clock = ControllableClock()
        let runner = ActionRunner(poster: poster, clock: clock)
        let chord = KeyChord(keyCode: 49, modifiers: 0, displayName: "Space")

        var settings = AppSettings.default
        settings.mode = .key
        settings.keyChord = chord
        settings.repeatMode = .count
        settings.repeatCount = 3
        settings.intervalMilliseconds = 5

        let finished = expectation(description: "finished")
        runner.start(settings: settings) {
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(poster.keys, [chord, chord, chord])
        XCTAssertEqual(clock.sleepCalls, [5, 5])
    }

    func testMacroRunsStepsInOrder() async {
        let poster = FakePoster()
        let clock = ControllableClock()
        let runner = ActionRunner(poster: poster, clock: clock)
        let chord = KeyChord(keyCode: 0, modifiers: 0, displayName: "A")

        var settings = AppSettings.default
        settings.mode = .macro
        settings.repeatMode = .count
        settings.repeatCount = 1
        settings.macroSteps = [
            .click(ScreenPoint(x: 1, y: 2), button: .left, intervalMilliseconds: 10),
            .wait(15),
            .key(chord, intervalMilliseconds: 20)
        ]

        let finished = expectation(description: "finished")
        runner.start(settings: settings) {
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(poster.clicks.count, 1)
        XCTAssertEqual(poster.clicks[0].point, CGPoint(x: 1, y: 2))
        XCTAssertEqual(clock.sleepCalls, [10, 15, 20])
        XCTAssertEqual(poster.keys, [chord])
    }

    func testMacroAppliesLoopIntervalBetweenRepeats() async {
        let poster = FakePoster()
        let clock = ControllableClock()
        let runner = ActionRunner(poster: poster, clock: clock)

        var settings = AppSettings.default
        settings.mode = .macro
        settings.repeatMode = .count
        settings.repeatCount = 2
        settings.macroLoopIntervalMilliseconds = 40
        settings.macroSteps = [
            .click(ScreenPoint(x: 1, y: 2), button: .left, intervalMilliseconds: 5)
        ]

        let finished = expectation(description: "finished")
        runner.start(settings: settings) {
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(poster.clicks.count, 2)
        // per-step interval after each click, plus loop gap between repeats
        XCTAssertEqual(clock.sleepCalls, [5, 40, 5])
    }

    func testStopCancelsRunner() async {
        let poster = FakePoster()
        let clock = ControllableClock()
        clock.sleepHandler = { _ in
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let runner = ActionRunner(poster: poster, clock: clock)

        var settings = AppSettings.default
        settings.mode = .clickHere
        settings.repeatMode = .untilStopped
        settings.intervalMilliseconds = 10

        runner.start(settings: settings) {}
        try? await Task.sleep(nanoseconds: 30_000_000)
        runner.stop()
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertFalse(runner.isRunning)
        XCTAssertGreaterThanOrEqual(poster.clicks.count, 1)
    }
}

final class ScreenCoordinateTests: XCTestCase {
    func testQuartzPointFlipsAppKitYAgainstPrimaryScreenHeight() {
        let quartz = ScreenCoordinates.quartzPoint(
            fromAppKit: CGPoint(x: 100, y: 40),
            primaryScreenHeight: 982
        )

        XCTAssertEqual(quartz.x, 100, accuracy: 0.001)
        XCTAssertEqual(quartz.y, 942, accuracy: 0.001)
    }

    func testQuartzPointKeepsCoordinatesAboveThePrimaryDisplay() {
        let quartz = ScreenCoordinates.quartzPoint(
            fromAppKit: CGPoint(x: 1600, y: 1034),
            primaryScreenHeight: 982
        )

        XCTAssertEqual(quartz.x, 1600, accuracy: 0.001)
        XCTAssertEqual(quartz.y, -52, accuracy: 0.001)
    }

    func testPickedPointUsesLiveQuartzCursorRatherThanEventLocation() {
        let picked = ScreenCoordinates.pickedPoint(
            cursorLocation: CGPoint(x: 2312, y: 448),
            eventLocation: CGPoint(x: 40, y: 20),
            appKitMouseLocation: CGPoint(x: 1, y: 2),
            primaryScreenHeight: 982
        )

        XCTAssertEqual(picked, CGPoint(x: 2312, y: 448))
    }
}

final class NumberParserTests: XCTestCase {
    func testIntegerAcceptsWholeNumbersOnly() {
        XCTAssertEqual(NumberParser.integer("0"), .valid(0))
        XCTAssertEqual(NumberParser.integer("-12"), .valid(-12))
        XCTAssertEqual(NumberParser.integer(" 40 "), .valid(40))
        XCTAssertEqual(NumberParser.integer(""), .incomplete)
        XCTAssertEqual(NumberParser.integer("-"), .incomplete)
        XCTAssertEqual(NumberParser.integer("10.5"), .invalid)
        XCTAssertEqual(NumberParser.integer("10a"), .invalid)
        XCTAssertEqual(NumberParser.integer("1,000"), .invalid)
    }

    func testDecimalAcceptsNumbersAndRejectsOtherText() {
        XCTAssertEqual(NumberParser.decimal("10"), .valid(10))
        XCTAssertEqual(NumberParser.decimal("-3.25"), .valid(-3.25))
        XCTAssertEqual(NumberParser.decimal("8,5"), .valid(8.5))
        XCTAssertEqual(NumberParser.decimal(""), .incomplete)
        XCTAssertEqual(NumberParser.decimal("1."), .incomplete)
        XCTAssertEqual(NumberParser.decimal("1.2.3"), .invalid)
        XCTAssertEqual(NumberParser.decimal("abc"), .invalid)
    }
}
