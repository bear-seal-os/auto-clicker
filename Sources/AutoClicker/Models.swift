import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum AppMode: String, Codable, CaseIterable, Identifiable {
    case clickHere
    case clickPoint
    case key
    case macro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clickHere: return "Click Here"
        case .clickPoint: return "Click Point"
        case .key: return "Key"
        case .macro: return "Macro"
        }
    }
}

enum MouseButton: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

enum RepeatMode: String, Codable, CaseIterable, Identifiable {
    case untilStopped
    case count

    var id: String { rawValue }

    var title: String {
        switch self {
        case .untilStopped: return "Until Stopped"
        case .count: return "Count"
        }
    }
}

struct ScreenPoint: Codable, Equatable, Hashable {
    var x: Double
    var y: Double

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }
}

struct KeyChord: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt
    var displayName: String
    /// Distinguishes an unset chord from keyCode 0 (A on a US keyboard).
    var isSet: Bool

    static let empty = KeyChord(keyCode: 0, modifiers: 0, displayName: "None", isSet: false)

    var isEmpty: Bool { !isSet }

    init(keyCode: UInt16, modifiers: UInt, displayName: String, isSet: Bool = true) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayName = displayName
        self.isSet = isSet
    }

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        let ns = NSEvent.ModifierFlags(rawValue: modifiers)
        if ns.contains(.command) { flags |= UInt32(cmdKey) }
        if ns.contains(.option) { flags |= UInt32(optionKey) }
        if ns.contains(.control) { flags |= UInt32(controlKey) }
        if ns.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}

enum MacroStepKind: String, Codable {
    case click
    case key
    case wait
}

struct MacroStep: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var kind: MacroStepKind
    var point: ScreenPoint?
    var mouseButton: MouseButton
    var key: KeyChord?
    /// Pause after this step (click/key). For wait steps, use `waitMilliseconds`.
    var intervalMilliseconds: Int
    var waitMilliseconds: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, point, mouseButton, key, intervalMilliseconds, waitMilliseconds
    }

    init(
        id: UUID = UUID(),
        kind: MacroStepKind,
        point: ScreenPoint? = nil,
        mouseButton: MouseButton = .left,
        key: KeyChord? = nil,
        intervalMilliseconds: Int = 100,
        waitMilliseconds: Int = 100
    ) {
        self.id = id
        self.kind = kind
        self.point = point
        self.mouseButton = mouseButton
        self.key = key
        self.intervalMilliseconds = intervalMilliseconds
        self.waitMilliseconds = waitMilliseconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(MacroStepKind.self, forKey: .kind)
        point = try container.decodeIfPresent(ScreenPoint.self, forKey: .point)
        mouseButton = try container.decodeIfPresent(MouseButton.self, forKey: .mouseButton) ?? .left
        key = try container.decodeIfPresent(KeyChord.self, forKey: .key)
        intervalMilliseconds = try container.decodeIfPresent(Int.self, forKey: .intervalMilliseconds) ?? 100
        waitMilliseconds = try container.decodeIfPresent(Int.self, forKey: .waitMilliseconds) ?? 100
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(point, forKey: .point)
        try container.encode(mouseButton, forKey: .mouseButton)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encode(intervalMilliseconds, forKey: .intervalMilliseconds)
        try container.encode(waitMilliseconds, forKey: .waitMilliseconds)
    }

    static func click(
        _ point: ScreenPoint,
        button: MouseButton = .left,
        intervalMilliseconds: Int = 100
    ) -> MacroStep {
        MacroStep(
            kind: .click,
            point: point,
            mouseButton: button,
            intervalMilliseconds: max(0, intervalMilliseconds)
        )
    }

    static func key(_ chord: KeyChord, intervalMilliseconds: Int = 100) -> MacroStep {
        MacroStep(kind: .key, key: chord, intervalMilliseconds: max(0, intervalMilliseconds))
    }

    static func wait(_ milliseconds: Int) -> MacroStep {
        MacroStep(kind: .wait, waitMilliseconds: max(0, milliseconds))
    }
}

struct AppSettings: Codable, Equatable {
    var mode: AppMode
    var intervalMilliseconds: Int
    var mouseButton: MouseButton
    var repeatMode: RepeatMode
    var repeatCount: Int
    var clickPoint: ScreenPoint
    var keyChord: KeyChord
    var macroSteps: [MacroStep]
    /// Pause between full macro repetitions.
    var macroLoopIntervalMilliseconds: Int
    var toggleHotkey: KeyChord

    static let minimumInterval = 10
    static let defaultInterval = 100

    static var `default`: AppSettings {
        AppSettings(
            mode: .clickHere,
            intervalMilliseconds: defaultInterval,
            mouseButton: .left,
            repeatMode: .untilStopped,
            repeatCount: 10,
            clickPoint: ScreenPoint(x: 0, y: 0),
            keyChord: .empty,
            macroSteps: [],
            macroLoopIntervalMilliseconds: defaultInterval,
            toggleHotkey: KeyChord(
                keyCode: 8,
                modifiers: UInt(NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue),
                displayName: "⌃⌥C"
            )
        )
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case intervalMilliseconds
        case mouseButton
        case repeatMode
        case repeatCount
        case clickPoint
        case keyChord
        case macroSteps
        case macroLoopIntervalMilliseconds
        case toggleHotkey
    }

    init(
        mode: AppMode,
        intervalMilliseconds: Int,
        mouseButton: MouseButton,
        repeatMode: RepeatMode,
        repeatCount: Int,
        clickPoint: ScreenPoint,
        keyChord: KeyChord,
        macroSteps: [MacroStep],
        macroLoopIntervalMilliseconds: Int,
        toggleHotkey: KeyChord
    ) {
        self.mode = mode
        self.intervalMilliseconds = intervalMilliseconds
        self.mouseButton = mouseButton
        self.repeatMode = repeatMode
        self.repeatCount = repeatCount
        self.clickPoint = clickPoint
        self.keyChord = keyChord
        self.macroSteps = macroSteps
        self.macroLoopIntervalMilliseconds = macroLoopIntervalMilliseconds
        self.toggleHotkey = toggleHotkey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(AppMode.self, forKey: .mode)
        intervalMilliseconds = try container.decode(Int.self, forKey: .intervalMilliseconds)
        mouseButton = try container.decode(MouseButton.self, forKey: .mouseButton)
        repeatMode = try container.decode(RepeatMode.self, forKey: .repeatMode)
        repeatCount = try container.decode(Int.self, forKey: .repeatCount)
        clickPoint = try container.decode(ScreenPoint.self, forKey: .clickPoint)
        keyChord = try container.decode(KeyChord.self, forKey: .keyChord)
        macroSteps = try container.decode([MacroStep].self, forKey: .macroSteps)
        macroLoopIntervalMilliseconds = try container.decodeIfPresent(
            Int.self,
            forKey: .macroLoopIntervalMilliseconds
        ) ?? Self.defaultInterval
        toggleHotkey = try container.decode(KeyChord.self, forKey: .toggleHotkey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(intervalMilliseconds, forKey: .intervalMilliseconds)
        try container.encode(mouseButton, forKey: .mouseButton)
        try container.encode(repeatMode, forKey: .repeatMode)
        try container.encode(repeatCount, forKey: .repeatCount)
        try container.encode(clickPoint, forKey: .clickPoint)
        try container.encode(keyChord, forKey: .keyChord)
        try container.encode(macroSteps, forKey: .macroSteps)
        try container.encode(macroLoopIntervalMilliseconds, forKey: .macroLoopIntervalMilliseconds)
        try container.encode(toggleHotkey, forKey: .toggleHotkey)
    }

    mutating func clamp() {
        intervalMilliseconds = max(Self.minimumInterval, intervalMilliseconds)
        macroLoopIntervalMilliseconds = max(0, macroLoopIntervalMilliseconds)
        repeatCount = max(1, repeatCount)
        for index in macroSteps.indices {
            macroSteps[index].intervalMilliseconds = max(0, macroSteps[index].intervalMilliseconds)
            macroSteps[index].waitMilliseconds = max(0, macroSteps[index].waitMilliseconds)
        }
    }
}
