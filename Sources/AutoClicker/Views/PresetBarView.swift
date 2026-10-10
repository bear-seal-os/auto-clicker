import SwiftUI
import UniformTypeIdentifiers

struct PresetExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct PresetBarView: View {
    @EnvironmentObject private var model: AppModel

    @State private var nameDraft = ""
    @State private var showsSaveAlert = false
    @State private var showsRenameAlert = false
    @State private var showsDeleteConfirm = false
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var exportDocument = PresetExportDocument(data: Data())

    private var presets: [ModePreset] {
        model.presetsForCurrentMode()
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { model.selectedPresetID },
            set: { model.selectPreset(id: $0) }
        )
    }

    private var canManage: Bool { model.canManagePresets }
    private var hasSelection: Bool { model.selectedPresetID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets")
                .font(.subheadline.weight(.semibold))

            Picker("Preset", selection: selection) {
                Text("None").tag(UUID?.none)
                ForEach(presets) { preset in
                    Text(preset.name).tag(Optional(preset.id))
                }
            }
            .labelsHidden()
            .disabled(!canManage)

            HStack(spacing: 6) {
                Button("Save") {
                    nameDraft = ""
                    showsSaveAlert = true
                }
                .disabled(!canManage)

                Button("Update") {
                    _ = model.updateSelectedPreset()
                }
                .disabled(!canManage || !hasSelection)

                Button("Rename") {
                    nameDraft = presets.first(where: { $0.id == model.selectedPresetID })?.name ?? ""
                    showsRenameAlert = true
                }
                .disabled(!canManage || !hasSelection)

                Button("Delete") {
                    showsDeleteConfirm = true
                }
                .disabled(!canManage || !hasSelection)

                Spacer(minLength: 0)

                Button("Export") {
                    guard let file = model.exportPresetsFile(),
                          let data = try? JSONEncoder().encode(file) else { return }
                    exportDocument = PresetExportDocument(data: data)
                    showsExporter = true
                }
                .disabled(presets.isEmpty)

                Button("Import") {
                    showsImporter = true
                }
                .disabled(!canManage)
            }
            .controlSize(.small)
            .font(.caption)
        }
        .alert("Save Preset", isPresented: $showsSaveAlert) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                _ = model.savePreset(named: nameDraft)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Name this preset for the \(model.settings.mode.title) tab.")
        }
        .alert("Rename Preset", isPresented: $showsRenameAlert) {
            TextField("Name", text: $nameDraft)
            Button("Rename") {
                _ = model.renameSelectedPreset(to: nameDraft)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Preset?", isPresented: $showsDeleteConfirm) {
            Button("Delete", role: .destructive) {
                model.deleteSelectedPreset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The live settings stay as they are.")
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case .failure = result {
                model.statusMessage = "Couldn’t export presets."
            } else {
                model.statusMessage = "Exported \(presets.count) preset\(presets.count == 1 ? "" : "s")."
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                guard let data = try? Data(contentsOf: url) else {
                    model.statusMessage = "Couldn’t import presets."
                    return
                }
                _ = model.importPresets(from: data)
            case .failure:
                model.statusMessage = "Couldn’t import presets."
            }
        }
        .onChange(of: model.settings.mode) { _, _ in
            clearStaleSelection()
        }
        .onChange(of: model.presetLibrary) { _, _ in
            clearStaleSelection()
        }
    }

    private var exportFilename: String {
        let slug = model.settings.mode.rawValue
        return "AutoClicker-\(slug)-presets"
    }

    private func clearStaleSelection() {
        guard let id = model.selectedPresetID else { return }
        if !presets.contains(where: { $0.id == id }) {
            model.selectedPresetID = nil
        }
    }
}
