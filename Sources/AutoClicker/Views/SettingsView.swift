import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            about
            Divider()
            updates
            Divider()
            permission
            Divider()
            links
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About")
                .font(.subheadline.weight(.semibold))
            Text("Repeats mouse clicks, key presses, and short macros from the menu bar or the Dock window.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            detailRow("Version", AppVersion.current())
            detailRow("Requires", "macOS 14 or later")
            detailRow("License", "MIT")
        }
    }

    private var updates: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Updates")
                .font(.subheadline.weight(.semibold))

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
            } else if model.updateCheckState == .upToDate {
                Text("You're up to date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.updateCheckState == .failed {
                Text("Couldn't check for updates. Try again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(model.updateCheckState == .checking ? "Checking…" : "Check for Updates") {
                Task { await model.checkForUpdate(showResult: true) }
            }
            .disabled(model.updateCheckState == .checking || model.isUpdating)
            .controlSize(.small)
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permission")
                .font(.subheadline.weight(.semibold))
            HStack {
                Image(systemName: model.hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.hasAccessibility ? Color.green : Color.orange)
                Text(model.hasAccessibility ? "Accessibility is on." : "Accessibility is off.")
                    .font(.caption)
                Spacer()
                if !model.hasAccessibility {
                    Button("Open System Settings") {
                        model.requestAccessibility()
                    }
                    .controlSize(.small)
                }
            }
            Text("Clicks, keys, and point picking need Accessibility access. Allow it once. Later updates keep this grant.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var links: some View {
        HStack {
            Button("View on GitHub") {
                model.openRepository()
            }
            .controlSize(.small)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
