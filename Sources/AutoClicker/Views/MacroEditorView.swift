import SwiftUI

struct MacroEditorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Loop interval (ms)")
                Spacer()
                TypedNumberField(
                    integer: $model.settings.macroLoopIntervalMilliseconds,
                    id: "macro.loopInterval",
                    width: 72,
                    enabled: !model.isRunning
                )
            }
            .font(.callout)

            Text("Each step has its own interval. Loop interval pauses between full macro repeats.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Steps")
                    .font(.subheadline.weight(.semibold))
                Text("\(model.settings.macroSteps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Click Point") { model.addMacroStep(.click) }
                    Button("Key") { model.addMacroStep(.key) }
                    Button("Wait") { model.addMacroStep(.wait) }
                } label: {
                    Label("Add Step", systemImage: "plus")
                }
                .disabled(model.isRunning)
            }

            if model.settings.macroSteps.isEmpty {
                Text("No steps yet. Add click, key, or wait actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(model.settings.macroSteps.enumerated()), id: \.element.id) { index, step in
                        MacroStepRow(index: index, stepID: step.id)
                    }
                }
            }
        }
    }
}

struct MacroStepRow: View {
    @EnvironmentObject private var model: AppModel
    let index: Int
    let stepID: UUID

    private var stepBinding: Binding<MacroStep>? {
        guard let idx = model.settings.macroSteps.firstIndex(where: { $0.id == stepID }) else {
            return nil
        }
        return $model.settings.macroSteps[idx]
    }

    var body: some View {
        Group {
            if let stepBinding {
                content(stepBinding)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func content(_ step: Binding<MacroStep>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(index + 1). \(kindTitle(step.wrappedValue.kind))")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    model.moveMacroStep(id: stepID, direction: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(model.isRunning || index == 0)
                .help("Move up")

                Button {
                    model.moveMacroStep(id: stepID, direction: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(model.isRunning || index >= model.settings.macroSteps.count - 1)
                .help("Move down")

                Button(role: .destructive) {
                    model.deleteMacroStep(id: stepID)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(model.isRunning)
                .help("Delete step")
            }

            switch step.wrappedValue.kind {
            case .click:
                HStack(spacing: 6) {
                    Text("X")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TypedNumberField(
                        decimal: Binding(
                            get: { step.wrappedValue.point?.x ?? 0 },
                            set: { newValue in
                                var point = step.wrappedValue.point ?? ScreenPoint(x: 0, y: 0)
                                point.x = newValue
                                step.wrappedValue.point = point
                            }
                        ),
                        id: "macro.\(stepID.uuidString).x",
                        enabled: !model.isRunning
                    )
                    Text("Y")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TypedNumberField(
                        decimal: Binding(
                            get: { step.wrappedValue.point?.y ?? 0 },
                            set: { newValue in
                                var point = step.wrappedValue.point ?? ScreenPoint(x: 0, y: 0)
                                point.y = newValue
                                step.wrappedValue.point = point
                            }
                        ),
                        id: "macro.\(stepID.uuidString).y",
                        enabled: !model.isRunning
                    )
                }
                HStack(spacing: 6) {
                    Picker("Button", selection: step.mouseButton) {
                        ForEach(MouseButton.allCases) { button in
                            Text(button.title).tag(button)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 72)
                    Button("Pick") {
                        model.pickPointForMacroStep(id: stepID)
                    }
                    .controlSize(.small)
                    Spacer()
                    Text("Interval")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TypedNumberField(
                        integer: step.intervalMilliseconds,
                        id: "macro.\(stepID.uuidString).interval",
                        width: 64,
                        enabled: !model.isRunning
                    )
                    Text("ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .key:
                KeyChordField(
                    title: "Key",
                    chord: Binding(
                        get: { step.wrappedValue.key ?? .empty },
                        set: { step.wrappedValue.key = $0 }
                    )
                )
                HStack {
                    Spacer()
                    Text("Interval")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TypedNumberField(
                        integer: step.intervalMilliseconds,
                        id: "macro.\(stepID.uuidString).interval",
                        width: 64,
                        enabled: !model.isRunning
                    )
                    Text("ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .wait:
                HStack {
                    Text("Wait")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TypedNumberField(
                        integer: step.waitMilliseconds,
                        id: "macro.\(stepID.uuidString).wait",
                        width: 64,
                        enabled: !model.isRunning
                    )
                    Text("ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func kindTitle(_ kind: MacroStepKind) -> String {
        switch kind {
        case .click: return "Click"
        case .key: return "Key"
        case .wait: return "Wait"
        }
    }
}
