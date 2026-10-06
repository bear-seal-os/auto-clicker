import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class PointPicker {
    private var monitor: Any?
    private var localMonitor: Any?

    var isPicking: Bool { monitor != nil || localMonitor != nil }

    func begin(completion: @escaping (ScreenPoint) -> Void) {
        cancel()

        let finish: (CGPoint) -> Void = { [weak self] point in
            self?.cancel()
            completion(ScreenPoint(point))
        }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            finish(Self.quartzLocation(from: event))
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            finish(Self.quartzLocation(from: event))
            return nil
        }
    }

    func cancel() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private static func quartzLocation(from event: NSEvent) -> CGPoint {
        ScreenCoordinates.pickedPoint(
            cursorLocation: CGEvent(source: nil)?.location,
            eventLocation: event.cgEvent?.location,
            appKitMouseLocation: NSEvent.mouseLocation,
            primaryScreenHeight: CGDisplayBounds(CGMainDisplayID()).height
        )
    }
}

enum ScreenCoordinates {
    /// AppKit screen points use the bottom-left of the primary display. CGEvent clicks use the top-left.
    static func quartzPoint(fromAppKit point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// The live cursor is already in the Quartz space used for clicks.
    /// A monitor event's own location can be window-relative and must not win.
    static func pickedPoint(
        cursorLocation: CGPoint?,
        eventLocation: CGPoint?,
        appKitMouseLocation: CGPoint,
        primaryScreenHeight: CGFloat
    ) -> CGPoint {
        if let cursorLocation {
            return cursorLocation
        }
        if let eventLocation {
            return eventLocation
        }
        return quartzPoint(fromAppKit: appKitMouseLocation, primaryScreenHeight: primaryScreenHeight)
    }
}

enum AccessibilityPermission {
    static func isTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
