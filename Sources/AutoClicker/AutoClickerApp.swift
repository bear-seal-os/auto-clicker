import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        showDockWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDockWindow()
        return true
    }

    private func showDockWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            PanelWindowAnchor.pinNearTop(window)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(
            rootView: ControlPanelView(enablesDefaultAction: true)
                .environment(\.numericFieldNamespace, "dock")
                .environmentObject(model)
        )
        // Build the window in one step. Assigning a hosting controller onto an
        // empty NSWindow crashes SwiftUI on macOS 26 while resolving window style.
        let window = NSWindow(contentViewController: host)
        window.title = "Auto Clicker"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: PanelLayout.width, height: PanelLayout.height))
        window.styleMask.remove(.resizable)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        PanelWindowAnchor.pinNearTop(window)
        DispatchQueue.main.async {
            PanelWindowAnchor.pinNearTop(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct AutoClickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ControlPanelView()
                .environment(\.numericFieldNamespace, "menu")
                .environmentObject(appDelegate.model)
        } label: {
            MenuBarIcon(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(systemName: model.isRunning ? "hand.tap.fill" : "cursorarrow.click")
    }
}
