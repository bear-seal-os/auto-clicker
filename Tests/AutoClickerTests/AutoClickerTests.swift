import CoreGraphics
import Darwin
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

final class PostedMouseEventTests: XCTestCase {
    func testPrepareAssignsUptimeTimestamp() throws {
        let prepared = try XCTUnwrap(
            CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: .zero,
                mouseButton: .left
            )
        )
        XCTAssertEqual(prepared.timestamp, 0)

        PostedMouseEvent.prepare(prepared, eventNumber: 7)

        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        XCTAssertGreaterThan(prepared.timestamp, 0)
        XCTAssertLessThanOrEqual(prepared.timestamp, now)
        XCTAssertEqual(prepared.getIntegerValueField(.mouseEventNumber), 7)
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

    func testOverlayDefaultsWhenMissingFromSavedJSON() throws {
        var legacy = AppSettings.default
        legacy.overlay = OverlaySettings(
            isEnabled: false,
            corner: .bottomLeft,
            opacity: 0.5,
            accent: .red
        )
        var encoded = try JSONEncoder().encode(legacy)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "overlay")
        encoded = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(decoded.overlay, .default)
    }

    func testOverlayOpacityClamps() {
        var settings = AppSettings.default
        settings.overlay.opacity = 0.1
        settings.clamp()
        XCTAssertEqual(settings.overlay.opacity, OverlaySettings.minimumOpacity)

        settings.overlay.opacity = 1.5
        settings.clamp()
        XCTAssertEqual(settings.overlay.opacity, OverlaySettings.maximumOpacity)
    }

    func testOverlayRoundTrip() throws {
        var settings = AppSettings.default
        settings.overlay = OverlaySettings(
            isEnabled: false,
            corner: .bottomRight,
            opacity: 0.55,
            accent: .purple
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.overlay, settings.overlay)
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

    func testIntervalModePublishesCues() async {
        let poster = FakePoster()
        let clock = ControllableClock()
        let runner = ActionRunner(poster: poster, clock: clock)
        var cues: [RunCue] = []

        var settings = AppSettings.default
        settings.mode = .clickHere
        settings.mouseButton = .left
        settings.repeatMode = .count
        settings.repeatCount = 2
        settings.intervalMilliseconds = 25

        let finished = expectation(description: "finished")
        runner.start(
            settings: settings,
            onCue: { cue in
                if let cue { cues.append(cue) }
            },
            onFinished: { finished.fulfill() }
        )
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].currentLabel, "Left click")
        XCTAssertEqual(cues[0].nextLabel, "Left click")
        XCTAssertEqual(cues[0].waitMilliseconds, 25)
        XCTAssertEqual(cues[1].currentLabel, "Left click")
        XCTAssertEqual(cues[1].nextLabel, "Done")
        XCTAssertEqual(cues[1].waitMilliseconds, 0)
    }

    func testMacroPublishesStepAndLoopCues() async {
        let poster = FakePoster()
        let clock = ControllableClock()
        let runner = ActionRunner(poster: poster, clock: clock)
        var cues: [RunCue] = []
        let chord = KeyChord(keyCode: 0, modifiers: 0, displayName: "A")

        var settings = AppSettings.default
        settings.mode = .macro
        settings.repeatMode = .count
        settings.repeatCount = 2
        settings.macroLoopIntervalMilliseconds = 40
        settings.macroSteps = [
            .click(ScreenPoint(x: 1, y: 2), button: .left, intervalMilliseconds: 5),
            .key(chord, intervalMilliseconds: 7)
        ]

        let finished = expectation(description: "finished")
        runner.start(
            settings: settings,
            onCue: { cue in
                if let cue { cues.append(cue) }
            },
            onFinished: { finished.fulfill() }
        )
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(cues.map(\.currentLabel), [
            "Left click (1, 2)",
            "A",
            "Loop pause",
            "Left click (1, 2)",
            "A"
        ])
        XCTAssertEqual(cues.map(\.nextLabel), [
            "A",
            "Loop pause",
            "Left click (1, 2)",
            "A",
            "Done"
        ])
        XCTAssertEqual(cues.map(\.waitMilliseconds), [5, 7, 40, 5, 0])
    }
}

final class RunLabelsTests: XCTestCase {
    func testIntervalAndMacroLabels() {
        var settings = AppSettings.default
        settings.mode = .clickPoint
        settings.mouseButton = .right
        settings.clickPoint = ScreenPoint(x: 10, y: 20)
        XCTAssertEqual(RunLabels.intervalAction(settings), "Right click (10, 20)")

        settings.mode = .key
        settings.keyChord = KeyChord(keyCode: 49, modifiers: 0, displayName: "Space")
        XCTAssertEqual(RunLabels.intervalAction(settings), "Space")

        XCTAssertEqual(RunLabels.macroStep(.wait(10)), "Wait")
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

final class AppUpdateTests: XCTestCase {
    func testNewerVersionComparison() {
        XCTAssertTrue(AppVersion.isNewer("1.1.0", than: "1.0.0"))
        XCTAssertTrue(AppVersion.isNewer("v1.10.0", than: "1.9.0"))
        XCTAssertTrue(AppVersion.isNewer("1.0.1", than: "1.0"))
        XCTAssertFalse(AppVersion.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(AppVersion.isNewer("v1.0.0", than: "1.1.0"))
    }

    func testReleaseFeedReturnsNewerZipOnly() throws {
        let data = Data(
            """
            {
              "tag_name": "v1.2.0",
              "assets": [
                {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
                {"name": "AutoClicker-macos.zip", "browser_download_url": "https://example.com/AutoClicker-macos.zip"}
              ]
            }
            """.utf8
        )

        let update = try XCTUnwrap(ReleaseFeed.availableUpdate(from: data, currentVersion: "1.1.0"))
        XCTAssertEqual(update.version, "1.2.0")
        XCTAssertEqual(update.downloadURL.absoluteString, "https://example.com/AutoClicker-macos.zip")
        XCTAssertNil(ReleaseFeed.availableUpdate(from: data, currentVersion: "1.2.0"))
        XCTAssertNil(ReleaseFeed.availableUpdate(from: data, currentVersion: "2.0.0"))
    }

    func testReleaseFeedIgnoresMissingAsset() {
        let data = Data(#"{"tag_name":"v9.0.0","assets":[]}"#.utf8)
        XCTAssertNil(ReleaseFeed.availableUpdate(from: data, currentVersion: "1.0.0"))
        XCTAssertEqual(ReleaseFeed.lookup(from: data, currentVersion: "1.0.0"), .unreadable)
    }

    func testReleaseFeedLookupReportsCurrentAndGarbage() {
        let current = Data(
            """
            {"tag_name":"v1.2.1","assets":[{"name":"AutoClicker-macos.zip","browser_download_url":"https://example.com/AutoClicker-macos.zip"}]}
            """.utf8
        )
        XCTAssertEqual(ReleaseFeed.lookup(from: current, currentVersion: "1.2.1"), .notNewer)
        XCTAssertEqual(ReleaseFeed.lookup(from: Data("nope".utf8), currentVersion: "1.2.1"), .unreadable)
    }
}

final class ModePresetTests: XCTestCase {
    private func baseSettings() -> AppSettings {
        var settings = AppSettings.default
        settings.intervalMilliseconds = 250
        settings.mouseButton = .right
        settings.repeatMode = .count
        settings.repeatCount = 7
        settings.clickPoint = ScreenPoint(x: 11, y: 22)
        settings.keyChord = KeyChord(keyCode: 0, modifiers: 0, displayName: "A")
        settings.macroSteps = [.wait(40)]
        settings.macroLoopIntervalMilliseconds = 80
        settings.toggleHotkey = KeyChord(keyCode: 9, modifiers: 262_144, displayName: "⌃V")
        settings.overlay = OverlaySettings(
            isEnabled: false,
            corner: .bottomLeft,
            opacity: 0.5,
            accent: .red
        )
        return settings
    }

    func testCaptureAndApplyClickHereLeavesOtherTargetsAlone() {
        var settings = baseSettings()
        settings.mode = .clickHere
        let preset = ModePreset.capture(name: "Here", from: settings)

        var target = AppSettings.default
        target.mode = .clickHere
        target.toggleHotkey = settings.toggleHotkey
        target.overlay = settings.overlay
        target.clickPoint = ScreenPoint(x: 99, y: 88)
        target.keyChord = KeyChord(keyCode: 1, modifiers: 0, displayName: "S")
        target.macroSteps = [.wait(1)]
        target.macroLoopIntervalMilliseconds = 999

        preset.apply(to: &target)

        XCTAssertEqual(target.intervalMilliseconds, 250)
        XCTAssertEqual(target.mouseButton, .right)
        XCTAssertEqual(target.repeatMode, .count)
        XCTAssertEqual(target.repeatCount, 7)
        XCTAssertEqual(target.clickPoint, ScreenPoint(x: 99, y: 88))
        XCTAssertEqual(target.keyChord.displayName, "S")
        XCTAssertEqual(target.macroSteps.count, 1)
        XCTAssertEqual(target.macroSteps[0].kind, .wait)
        XCTAssertEqual(target.macroSteps[0].waitMilliseconds, 1)
        XCTAssertEqual(target.macroLoopIntervalMilliseconds, 999)
        XCTAssertEqual(target.toggleHotkey, settings.toggleHotkey)
        XCTAssertEqual(target.overlay, settings.overlay)
    }

    func testCaptureAndApplyClickPoint() {
        var settings = baseSettings()
        settings.mode = .clickPoint
        let preset = ModePreset.capture(name: "Point", from: settings)

        var target = AppSettings.default
        target.mode = .clickPoint
        target.keyChord = settings.keyChord
        target.macroSteps = settings.macroSteps
        preset.apply(to: &target)

        XCTAssertEqual(target.clickPoint, ScreenPoint(x: 11, y: 22))
        XCTAssertEqual(target.keyChord, settings.keyChord)
        XCTAssertEqual(target.macroSteps, settings.macroSteps)
    }

    func testCaptureAndApplyKey() {
        var settings = baseSettings()
        settings.mode = .key
        let preset = ModePreset.capture(name: "Key", from: settings)

        var target = AppSettings.default
        target.mode = .key
        target.clickPoint = settings.clickPoint
        preset.apply(to: &target)

        XCTAssertEqual(target.keyChord, settings.keyChord)
        XCTAssertEqual(target.clickPoint, settings.clickPoint)
    }

    func testCaptureAndApplyMacro() {
        var settings = baseSettings()
        settings.mode = .macro
        settings.macroSteps = [
            .click(ScreenPoint(x: 1, y: 2), button: .left),
            .wait(15)
        ]
        settings.macroLoopIntervalMilliseconds = 33
        let preset = ModePreset.capture(name: "Macro", from: settings)

        var target = AppSettings.default
        target.mode = .macro
        target.clickPoint = ScreenPoint(x: 50, y: 60)
        target.keyChord = settings.keyChord
        preset.apply(to: &target)

        XCTAssertEqual(target.macroSteps, settings.macroSteps)
        XCTAssertEqual(target.macroLoopIntervalMilliseconds, 33)
        XCTAssertEqual(target.clickPoint, ScreenPoint(x: 50, y: 60))
        XCTAssertEqual(target.keyChord, settings.keyChord)
    }

    func testLibrarySaveRejectsBlankAndDuplicateNames() {
        var library = PresetLibrary.empty
        var settings = baseSettings()
        settings.mode = .clickHere

        XCTAssertThrowsError(try library.save(name: "  ", from: settings)) { error in
            XCTAssertEqual(error as? PresetError, .blankName)
        }
        XCTAssertNoThrow(try library.save(name: "A", from: settings))
        XCTAssertThrowsError(try library.save(name: "A", from: settings)) { error in
            XCTAssertEqual(error as? PresetError, .duplicateName)
        }
        XCTAssertEqual(library.presets(for: .clickHere).count, 1)
    }

    func testLibraryUpdateRenameAndDelete() throws {
        var library = PresetLibrary.empty
        var settings = baseSettings()
        settings.mode = .key
        let id = try library.save(name: "Original", from: settings)

        settings.intervalMilliseconds = 500
        try library.update(id: id, from: settings)
        XCTAssertEqual(library.presets(for: .key).first?.intervalMilliseconds, 500)

        try library.rename(id: id, to: "Renamed")
        XCTAssertEqual(library.presets(for: .key).first?.name, "Renamed")

        XCTAssertThrowsError(try library.rename(id: id, to: "  ")) { error in
            XCTAssertEqual(error as? PresetError, .blankName)
        }

        library.delete(id: id, mode: .key)
        XCTAssertTrue(library.presets(for: .key).isEmpty)
    }

    func testPresetLibraryStorePersists() throws {
        let defaults = UserDefaults(suiteName: "AutoClickerPresetTests.\(UUID().uuidString)")!
        var library = PresetLibrary.empty
        var settings = baseSettings()
        settings.mode = .clickPoint
        _ = try library.save(name: "P1", from: settings)
        PresetLibraryStore.save(library, defaults: defaults)

        let loaded = PresetLibraryStore.load(defaults: defaults)
        XCTAssertEqual(loaded.presets(for: .clickPoint).count, 1)
        XCTAssertEqual(loaded.presets(for: .clickPoint).first?.name, "P1")
    }

    func testPresetFileRoundTripAndImportMergesNames() throws {
        var library = PresetLibrary.empty
        var settings = baseSettings()
        settings.mode = .macro
        let firstID = try library.save(name: "Farm", from: settings)
        settings.macroLoopIntervalMilliseconds = 12
        _ = try library.save(name: "Boss", from: settings)

        let file = PresetFile(mode: .macro, presets: library.presets(for: .macro))
        let data = try JSONEncoder().encode(file)
        let decoded = try PresetFile.decode(from: data)
        XCTAssertEqual(decoded.mode, .macro)
        XCTAssertEqual(decoded.presets.count, 2)

        var target = PresetLibrary.empty
        let existingID = try target.save(name: "Farm", from: settings)
        let imported = try target.importPresets(from: decoded, into: .macro)
        XCTAssertEqual(imported, 2)
        let names = target.presets(for: .macro).map(\.name).sorted()
        XCTAssertEqual(names, ["Boss", "Farm", "Farm 2"])
        let importedIDs = Set(target.presets(for: .macro).map(\.id))
        XCTAssertTrue(importedIDs.contains(existingID))
        XCTAssertFalse(importedIDs.contains(firstID))
        XCTAssertEqual(importedIDs.count, 3)
    }

    func testImportRejectsMismatchedModeAndBadFile() throws {
        var library = PresetLibrary.empty
        var settings = baseSettings()
        settings.mode = .key
        _ = try library.save(name: "K", from: settings)
        let file = PresetFile(mode: .key, presets: library.presets(for: .key))

        var target = PresetLibrary.empty
        XCTAssertThrowsError(try target.importPresets(from: file, into: .clickHere)) { error in
            XCTAssertEqual(error as? PresetError, .mismatchedMode)
        }
        XCTAssertTrue(target.presets(for: .clickHere).isEmpty)

        XCTAssertThrowsError(try PresetFile.decode(from: Data("{}".utf8))) { error in
            XCTAssertEqual(error as? PresetError, .invalidFile)
        }
    }
}
