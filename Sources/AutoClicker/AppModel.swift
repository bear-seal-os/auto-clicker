import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persistAndRefreshHotkey() }
    }
    @Published var presetLibrary: PresetLibrary {
        didSet { PresetLibraryStore.save(presetLibrary) }
    }
    /// Session-only selection per mode; not persisted.
    @Published var selectedPresetIDs: [AppMode: UUID] = [:]
    @Published var isRunning = false
    @Published var isPickingPoint = false
    @Published var hasAccessibility = false
    @Published var statusMessage: String?
    @Published var availableUpdate: AvailableUpdate?
    @Published var updateCheckState: UpdateCheckState = .idle
    @Published var isUpdating = false
    @Published var runCue: RunCue?
    @Published private(set) var invalidNumericFieldIDs: Set<String> = []

    private let poster: InputPosting
    private let runner: ActionRunner
    private let pointPicker = PointPicker()
    private let hotkey = HotkeyController()
    private let updates = GitHubUpdateClient()
    private var accessibilityTimer: Timer?
    private let overlayController = RunOverlayController()

    init(poster: InputPosting = InputPoster(), settings: AppSettings? = nil) {
        self.poster = poster
        self.runner = ActionRunner(poster: poster)
        var loaded = settings ?? SettingsStore.load()
        loaded.clamp()
        self.settings = loaded
        self.presetLibrary = PresetLibraryStore.load()
        if Bundle.main.bundleURL.pathExtension == "app" {
            AccessibilityPermission.resetStaleGrantIfNeeded()
        }
        refreshAccessibility()
        registerHotkey()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibility()
            }
        }
        if Bundle.main.bundleURL.pathExtension == "app" {
            Task { await checkForUpdate() }
        }
        overlayController.bind(to: self)
    }

    var canManagePresets: Bool {
        !isRunning && !isPickingPoint && !hasInvalidNumericInput
    }

    var selectedPresetID: UUID? {
        get { selectedPresetIDs[settings.mode] }
        set { selectedPresetIDs[settings.mode] = newValue }
    }

    func presetsForCurrentMode() -> [ModePreset] {
        presetLibrary.presets(for: settings.mode)
    }

    func selectPreset(id: UUID?) {
        guard canManagePresets else { return }
        guard let id else {
            selectedPresetID = nil
            return
        }
        guard let preset = presetsForCurrentMode().first(where: { $0.id == id }) else { return }
        selectedPresetID = id
        preset.apply(to: &settings)
        statusMessage = "Loaded preset “\(preset.name)”."
    }

    @discardableResult
    func savePreset(named name: String) -> Bool {
        guard canManagePresets else { return false }
        do {
            let id = try presetLibrary.save(name: name, from: settings)
            selectedPresetID = id
            statusMessage = "Saved preset “\(name.trimmingCharacters(in: .whitespacesAndNewlines))”."
            return true
        } catch PresetError.blankName {
            statusMessage = "Preset name can’t be empty."
            return false
        } catch PresetError.duplicateName {
            statusMessage = "A preset with that name already exists."
            return false
        } catch {
            statusMessage = "Couldn’t save preset."
            return false
        }
    }

    @discardableResult
    func updateSelectedPreset() -> Bool {
        guard canManagePresets, let id = selectedPresetID else { return false }
        do {
            try presetLibrary.update(id: id, from: settings)
            let name = presetsForCurrentMode().first(where: { $0.id == id })?.name ?? "preset"
            statusMessage = "Updated “\(name)”."
            return true
        } catch {
            statusMessage = "Couldn’t update preset."
            return false
        }
    }

    @discardableResult
    func renameSelectedPreset(to name: String) -> Bool {
        guard canManagePresets, let id = selectedPresetID else { return false }
        do {
            try presetLibrary.rename(id: id, to: name)
            statusMessage = "Renamed preset to “\(name.trimmingCharacters(in: .whitespacesAndNewlines))”."
            return true
        } catch PresetError.blankName {
            statusMessage = "Preset name can’t be empty."
            return false
        } catch PresetError.duplicateName {
            statusMessage = "A preset with that name already exists."
            return false
        } catch {
            statusMessage = "Couldn’t rename preset."
            return false
        }
    }

    func deleteSelectedPreset() {
        guard canManagePresets, let id = selectedPresetID else { return }
        let name = presetsForCurrentMode().first(where: { $0.id == id })?.name
        presetLibrary.delete(id: id, mode: settings.mode)
        selectedPresetID = nil
        if let name {
            statusMessage = "Deleted preset “\(name)”."
        }
    }

    func exportPresetsFile() -> PresetFile? {
        let presets = presetsForCurrentMode()
        guard !presets.isEmpty else { return nil }
        return PresetFile(mode: settings.mode, presets: presets)
    }

    @discardableResult
    func importPresets(from data: Data) -> Bool {
        guard canManagePresets else { return false }
        do {
            let file = try PresetFile.decode(from: data)
            let count = try presetLibrary.importPresets(from: file, into: settings.mode)
            statusMessage = count == 1
                ? "Imported 1 preset."
                : "Imported \(count) presets."
            return true
        } catch PresetError.mismatchedMode {
            statusMessage = "That file is for a different tab."
            return false
        } catch PresetError.unsupportedVersion {
            statusMessage = "That preset file version isn’t supported."
            return false
        } catch {
            statusMessage = "Couldn’t import presets."
            return false
        }
    }

    func shutdown() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        hotkey.unregister()
        pointPicker.cancel()
        runner.stop()
        runCue = nil
        overlayController.shutdown()
    }

    var hasInvalidNumericInput: Bool { !invalidNumericFieldIDs.isEmpty }

    func setNumericFieldInvalid(_ id: String, invalid: Bool) {
        if invalid {
            guard !invalidNumericFieldIDs.contains(id) else { return }
            invalidNumericFieldIDs.insert(id)
        } else {
            guard invalidNumericFieldIDs.contains(id) else { return }
            invalidNumericFieldIDs.remove(id)
        }
    }

    var canStart: Bool {
        guard hasAccessibility, !isPickingPoint, !hasInvalidNumericInput else { return false }
        switch settings.mode {
        case .clickHere, .clickPoint:
            return true
        case .key:
            return !settings.keyChord.isEmpty
        case .macro:
            return !settings.macroSteps.isEmpty
        }
    }

    func refreshAccessibility() {
        hasAccessibility = AccessibilityPermission.isTrusted(prompt: false)
    }

    func requestAccessibility() {
        _ = AccessibilityPermission.isTrusted(prompt: true)
        AccessibilityPermission.openSettings()
        refreshAccessibility()
    }

    func checkForUpdate(showResult: Bool = false) async {
        if showResult {
            updateCheckState = .checking
        }
        switch await updates.check(currentVersion: AppVersion.current()) {
        case .available(let update):
            availableUpdate = update
            updateCheckState = .idle
        case .upToDate:
            availableUpdate = nil
            if showResult {
                updateCheckState = .upToDate
            }
        case .failed:
            if showResult {
                updateCheckState = .failed
            }
        }
    }

    func openRepository() {
        NSWorkspace.shared.open(GitHubUpdateClient.repositoryURL)
    }

    func installUpdate() {
        guard let update = availableUpdate, !isUpdating else { return }
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            statusMessage = "Install the app to update it from here."
            return
        }
        isUpdating = true
        statusMessage = nil
        Task {
            do {
                stop()
                try await AppBundleUpdater.install(update: update, replacing: appURL)
                NSApp.terminate(nil)
            } catch {
                isUpdating = false
                statusMessage = "Update failed. Download the latest release from GitHub."
            }
        }
    }

    func toggleRunning() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard canStart, !isRunning else { return }
        var snapshot = settings
        snapshot.clamp()
        isRunning = true
        statusMessage = nil
        runCue = nil
        runner.start(
            settings: snapshot,
            onCue: { [weak self] cue in
                Task { @MainActor in
                    self?.runCue = cue
                }
            },
            onFinished: { [weak self] in
                self?.isRunning = false
                self?.runCue = nil
            }
        )
    }

    func stop() {
        runner.stop()
        isRunning = false
        runCue = nil
    }

    func beginPickClickPoint() {
        guard hasAccessibility else {
            requestAccessibility()
            return
        }
        isPickingPoint = true
        statusMessage = "Click anywhere to set the point…"
        pointPicker.begin { [weak self] point in
            Task { @MainActor in
                guard let self else { return }
                self.settings.clickPoint = point
                self.isPickingPoint = false
                self.statusMessage = String(format: "Point set to %.0f, %.0f", point.x, point.y)
            }
        }
    }

    func cancelPick() {
        pointPicker.cancel()
        isPickingPoint = false
        statusMessage = nil
    }

    func addMacroStep(_ kind: MacroStepKind) {
        let defaultInterval = settings.intervalMilliseconds
        switch kind {
        case .click:
            settings.macroSteps.append(
                .click(settings.clickPoint, button: settings.mouseButton, intervalMilliseconds: defaultInterval)
            )
        case .key:
            let key = settings.keyChord.isEmpty
                ? KeyChord(keyCode: 49, modifiers: 0, displayName: "Space")
                : settings.keyChord
            settings.macroSteps.append(.key(key, intervalMilliseconds: defaultInterval))
        case .wait:
            settings.macroSteps.append(.wait(defaultInterval))
        }
    }

    func deleteMacroSteps(at offsets: IndexSet) {
        settings.macroSteps.remove(atOffsets: offsets)
    }

    func deleteMacroStep(id: UUID) {
        settings.macroSteps.removeAll { $0.id == id }
    }

    func moveMacroStep(from source: IndexSet, to destination: Int) {
        settings.macroSteps.move(fromOffsets: source, toOffset: destination)
    }

    func moveMacroStep(id: UUID, direction: Int) {
        guard let index = settings.macroSteps.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + direction
        guard settings.macroSteps.indices.contains(destination) else { return }
        settings.macroSteps.swapAt(index, destination)
    }

    func pickPointForMacroStep(id: UUID) {
        guard hasAccessibility else {
            requestAccessibility()
            return
        }
        isPickingPoint = true
        statusMessage = "Click anywhere for this macro step…"
        pointPicker.begin { [weak self] point in
            Task { @MainActor in
                guard let self else { return }
                if let index = self.settings.macroSteps.firstIndex(where: { $0.id == id }) {
                    self.settings.macroSteps[index].point = point
                }
                self.isPickingPoint = false
                self.statusMessage = String(format: "Step point %.0f, %.0f", point.x, point.y)
            }
        }
    }

    private func persistAndRefreshHotkey() {
        SettingsStore.save(settings)
        registerHotkey()
    }

    private func registerHotkey() {
        hotkey.register(chord: settings.toggleHotkey) { [weak self] in
            Task { @MainActor in
                self?.toggleRunning()
            }
        }
    }
}
