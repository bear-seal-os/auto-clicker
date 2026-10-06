import AppKit
import SwiftUI

struct KeyChordField: View {
    let title: String
    @Binding var chord: KeyChord
    var requireModifier: Bool = false

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(isRecording ? "Press keys…" : chord.displayName) {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .orange : .secondary)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if requireModifier && modifiers.isEmpty {
                return nil
            }
            // Ignore pure modifier presses.
            let keyCode = event.keyCode
            let modifierOnly: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            if modifierOnly.contains(keyCode) {
                return nil
            }
            chord = KeyChord(
                keyCode: keyCode,
                modifiers: modifiers.rawValue,
                displayName: KeyDisplay.name(keyCode: keyCode, modifiers: modifiers)
            )
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}
