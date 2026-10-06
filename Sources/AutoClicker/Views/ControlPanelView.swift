import AppKit
import SwiftUI

private enum PanelSection: Hashable {
    case mode(AppMode)
    case settings
}

struct ControlPanelView: View {
    @EnvironmentObject private var model: AppModel
    /// Return-to-start crashes SwiftUI when this view is hosted in a
    /// `MenuBarExtra` window. The Dock window can keep it.
    var enablesDefaultAction = false
    @State private var showsSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            sectionPicker
            if showsSettings {
                SettingsView()
            } else {
                sharedControls
                modeSpecificControls
                Divider()
                hotkeySection
                footer
            }
        }
        .padding(14)
        .frame(width: 460)
    }

    private var section: Binding<PanelSection> {
        Binding(
            get: { showsSettings ? .settings : .mode(model.settings.mode) },
            set: { newValue in
                switch newValue {
                case .mode(let mode):
                    if model.isRunning, mode != model.settings.mode { return }
                    showsSettings = false
                    model.settings.mode = mode
                case .settings:
                    showsSettings = true
                }
            }
        )
    }

    private var sectionPicker: some View {
        Picker("Mode", selection: section) {
            ForEach(AppMode.allCases) { mode in
                Text(mode.title).tag(PanelSection.mode(mode))
            }
            Text("Settings").tag(PanelSection.settings)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var header: some View {
        HStack {
            Text("Auto Clicker")
                .font(.headline)
            Text(AppVersion.current())
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.isRunning {
                Text("Running")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var sharedControls: some View {
        Group {
            if model.settings.mode != .macro {
                HStack {
                    Text("Interval (ms)")
                    Spacer()
                    TypedNumberField(
                        integer: $model.settings.intervalMilliseconds,
                        id: "interval",
                        width: 80,
                        enabled: !model.isRunning
                    )
                }
            }

            HStack {
                Text("Mouse Button")
                Spacer()
                Picker("", selection: $model.settings.mouseButton) {
                    ForEach(MouseButton.allCases) { button in
                        Text(button.title).tag(button)
                    }
                }
                .frame(width: 100)
                .disabled(model.settings.mode == .key || model.isRunning)
            }

            HStack {
                Text("Repeat")
                Spacer()
                Picker("", selection: $model.settings.repeatMode) {
                    ForEach(RepeatMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .frame(width: 140)
                .disabled(model.isRunning)

                if model.settings.repeatMode == .count {
                    TypedNumberField(
                        integer: $model.settings.repeatCount,
                        id: "repeatCount",
                        width: 60,
                        enabled: !model.isRunning
                    )
                }
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private var modeSpecificControls: some View {
        switch model.settings.mode {
        case .clickHere:
            Text("Clicks follow the live cursor position.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .clickPoint:
            ClickPointEditor()
        case .key:
            KeyChordField(title: "Key", chord: $model.settings.keyChord)
                .disabled(model.isRunning)
        case .macro:
            MacroEditorView()
        }
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Toggle Hotkey")
                .font(.subheadline.weight(.semibold))
            KeyChordField(title: "Shortcut", chord: $model.settings.toggleHotkey, requireModifier: true)
                .disabled(model.isRunning)
            Text("Must include at least one modifier. Same shortcut starts and stops.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let update = model.availableUpdate {
                HStack {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.blue)
                    Text("Version \(update.version) is available")
                        .font(.caption)
                    Spacer()
                    Button(model.isUpdating ? "Updating…" : "Update") {
                        model.installUpdate()
                    }
                    .disabled(model.isUpdating)
                    .controlSize(.small)
                }
            }

            if !model.hasAccessibility {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Accessibility permission required")
                        .font(.caption)
                    Spacer()
                    Button("Open Settings") {
                        model.requestAccessibility()
                    }
                    .controlSize(.small)
                }
            }

            if model.hasInvalidNumericInput {
                Text("Intervals and counts must be whole numbers. Coordinates must be numbers.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let status = model.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if model.isPickingPoint {
                    Button("Cancel Pick") {
                        model.cancelPick()
                    }
                }
                Spacer()
                Button(model.isRunning ? "Stop" : "Start") {
                    model.toggleRunning()
                }
                .modifier(DefaultActionShortcut(isEnabled: enablesDefaultAction))
                .disabled(!model.isRunning && !model.canStart)
                .buttonStyle(.borderedProminent)
                .tint(model.isRunning ? .red : .accentColor)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

private struct DefaultActionShortcut: ViewModifier {
    var isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.keyboardShortcut(.defaultAction)
        } else {
            content
        }
    }
}

struct ClickPointEditor: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("X")
                TypedNumberField(
                    decimal: $model.settings.clickPoint.x,
                    id: "clickPoint.x",
                    enabled: !model.isRunning
                )
                Text("Y")
                TypedNumberField(
                    decimal: $model.settings.clickPoint.y,
                    id: "clickPoint.y",
                    enabled: !model.isRunning
                )
                Button(model.isPickingPoint ? "Picking…" : "Pick") {
                    model.beginPickClickPoint()
                }
                .disabled(model.isRunning || model.isPickingPoint)
            }
            Text("Coordinates use the top-left of the main display.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .disabled(model.isRunning)
    }
}
