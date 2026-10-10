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

enum OverlayCorner: String, Codable, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

enum OverlayAccent: String, Codable, CaseIterable, Identifiable {
    case blue
    case green
    case orange
    case red
    case purple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .red: return "Red"
        case .purple: return "Purple"
        }
    }
}

struct OverlaySettings: Codable, Equatable {
    var isEnabled: Bool
    var corner: OverlayCorner
    var opacity: Double
    var accent: OverlayAccent

    static let minimumOpacity = 0.4
    static let maximumOpacity = 1.0
    static let defaultOpacity = 0.9

    static var `default`: OverlaySettings {
        OverlaySettings(
            isEnabled: true,
            corner: .topRight,
            opacity: defaultOpacity,
            accent: .blue
        )
    }

    mutating func clamp() {
        opacity = min(Self.maximumOpacity, max(Self.minimumOpacity, opacity))
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
    var overlay: OverlaySettings

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
            ),
            overlay: .default
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
        case overlay
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
        toggleHotkey: KeyChord,
        overlay: OverlaySettings = .default
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
        self.overlay = overlay
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
        overlay = try container.decodeIfPresent(OverlaySettings.self, forKey: .overlay) ?? .default
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
        try container.encode(overlay, forKey: .overlay)
    }

    mutating func clamp() {
        intervalMilliseconds = max(Self.minimumInterval, intervalMilliseconds)
        macroLoopIntervalMilliseconds = max(0, macroLoopIntervalMilliseconds)
        repeatCount = max(1, repeatCount)
        overlay.clamp()
        for index in macroSteps.indices {
            macroSteps[index].intervalMilliseconds = max(0, macroSteps[index].intervalMilliseconds)
            macroSteps[index].waitMilliseconds = max(0, macroSteps[index].waitMilliseconds)
        }
    }
}

enum PresetError: Error, Equatable {
    case blankName
    case duplicateName
    case notFound
    case mismatchedMode
    case invalidFile
    case unsupportedVersion
}

enum ModePresetDetails: Codable, Equatable, Hashable {
    case clickHere
    case clickPoint(ScreenPoint)
    case key(KeyChord)
    case macro(steps: [MacroStep], loopIntervalMilliseconds: Int)

    var mode: AppMode {
        switch self {
        case .clickHere: return .clickHere
        case .clickPoint: return .clickPoint
        case .key: return .key
        case .macro: return .macro
        }
    }
}

struct ModePreset: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var intervalMilliseconds: Int
    var mouseButton: MouseButton
    var repeatMode: RepeatMode
    var repeatCount: Int
    var details: ModePresetDetails

    var mode: AppMode { details.mode }

    static func capture(name: String, from settings: AppSettings) -> ModePreset {
        let details: ModePresetDetails
        switch settings.mode {
        case .clickHere:
            details = .clickHere
        case .clickPoint:
            details = .clickPoint(settings.clickPoint)
        case .key:
            details = .key(settings.keyChord)
        case .macro:
            details = .macro(
                steps: settings.macroSteps,
                loopIntervalMilliseconds: settings.macroLoopIntervalMilliseconds
            )
        }
        var preset = ModePreset(
            id: UUID(),
            name: name,
            intervalMilliseconds: settings.intervalMilliseconds,
            mouseButton: settings.mouseButton,
            repeatMode: settings.repeatMode,
            repeatCount: settings.repeatCount,
            details: details
        )
        preset.clamp()
        return preset
    }

    func apply(to settings: inout AppSettings) {
        var copy = self
        copy.clamp()
        settings.intervalMilliseconds = copy.intervalMilliseconds
        settings.mouseButton = copy.mouseButton
        settings.repeatMode = copy.repeatMode
        settings.repeatCount = copy.repeatCount
        switch copy.details {
        case .clickHere:
            break
        case .clickPoint(let point):
            settings.clickPoint = point
        case .key(let chord):
            settings.keyChord = chord
        case .macro(let steps, let loopInterval):
            settings.macroSteps = steps
            settings.macroLoopIntervalMilliseconds = loopInterval
        }
    }

    mutating func clamp() {
        intervalMilliseconds = max(AppSettings.minimumInterval, intervalMilliseconds)
        repeatCount = max(1, repeatCount)
        switch details {
        case .clickHere, .clickPoint, .key:
            break
        case .macro(var steps, let loopInterval):
            for index in steps.indices {
                steps[index].intervalMilliseconds = max(0, steps[index].intervalMilliseconds)
                steps[index].waitMilliseconds = max(0, steps[index].waitMilliseconds)
            }
            details = .macro(steps: steps, loopIntervalMilliseconds: max(0, loopInterval))
        }
    }
}

struct PresetLibrary: Codable, Equatable {
    var clickHere: [ModePreset]
    var clickPoint: [ModePreset]
    var key: [ModePreset]
    var macro: [ModePreset]

    static var empty: PresetLibrary {
        PresetLibrary(clickHere: [], clickPoint: [], key: [], macro: [])
    }

    func presets(for mode: AppMode) -> [ModePreset] {
        switch mode {
        case .clickHere: return clickHere
        case .clickPoint: return clickPoint
        case .key: return key
        case .macro: return macro
        }
    }

    mutating func setPresets(_ presets: [ModePreset], for mode: AppMode) {
        switch mode {
        case .clickHere: clickHere = presets
        case .clickPoint: clickPoint = presets
        case .key: key = presets
        case .macro: macro = presets
        }
    }

    mutating func clamp() {
        for mode in AppMode.allCases {
            var presets = presets(for: mode)
            for index in presets.indices {
                presets[index].clamp()
            }
            setPresets(presets, for: mode)
        }
    }

    @discardableResult
    mutating func save(name: String, from settings: AppSettings) throws -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PresetError.blankName }
        let mode = settings.mode
        guard !presets(for: mode).contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw PresetError.duplicateName
        }
        var preset = ModePreset.capture(name: trimmed, from: settings)
        preset.name = trimmed
        var list = presets(for: mode)
        list.append(preset)
        setPresets(list, for: mode)
        return preset.id
    }

    mutating func update(id: UUID, from settings: AppSettings) throws {
        let mode = settings.mode
        var list = presets(for: mode)
        guard let index = list.firstIndex(where: { $0.id == id }) else {
            throw PresetError.notFound
        }
        let name = list[index].name
        var preset = ModePreset.capture(name: name, from: settings)
        preset.id = id
        preset.name = name
        list[index] = preset
        setPresets(list, for: mode)
    }

    mutating func rename(id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PresetError.blankName }
        for mode in AppMode.allCases {
            var list = presets(for: mode)
            guard let index = list.firstIndex(where: { $0.id == id }) else { continue }
            guard !list.contains(where: {
                $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
            }) else {
                throw PresetError.duplicateName
            }
            list[index].name = trimmed
            setPresets(list, for: mode)
            return
        }
        throw PresetError.notFound
    }

    mutating func delete(id: UUID, mode: AppMode) {
        var list = presets(for: mode)
        list.removeAll { $0.id == id }
        setPresets(list, for: mode)
    }

    @discardableResult
    mutating func importPresets(from file: PresetFile, into mode: AppMode) throws -> Int {
        guard file.mode == mode else { throw PresetError.mismatchedMode }
        var list = presets(for: mode)
        for imported in file.presets {
            var preset = imported
            preset.id = UUID()
            preset.name = Self.uniqueName(preset.name, among: list)
            preset.clamp()
            list.append(preset)
        }
        setPresets(list, for: mode)
        return file.presets.count
    }

    static func uniqueName(_ base: String, among presets: [ModePreset]) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = trimmed.isEmpty ? "Preset" : trimmed
        func taken(_ name: String) -> Bool {
            presets.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        if !taken(seed) { return seed }
        var suffix = 2
        while taken("\(seed) \(suffix)") {
            suffix += 1
        }
        return "\(seed) \(suffix)"
    }
}

struct PresetFile: Codable, Equatable {
    static let formatID = "autoclicker.presets"
    static let currentVersion = 1

    var format: String
    var version: Int
    var mode: AppMode
    var presets: [ModePreset]

    init(mode: AppMode, presets: [ModePreset]) {
        self.format = Self.formatID
        self.version = Self.currentVersion
        self.mode = mode
        self.presets = presets
    }

    static func decode(from data: Data) throws -> PresetFile {
        let file: PresetFile
        do {
            file = try JSONDecoder().decode(PresetFile.self, from: data)
        } catch {
            throw PresetError.invalidFile
        }
        guard file.format == formatID else { throw PresetError.invalidFile }
        guard file.version == currentVersion else { throw PresetError.unsupportedVersion }
        return file
    }
}
