import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

protocol InputPosting: AnyObject {
    func click(at point: CGPoint, button: MouseButton)
    func pressKey(_ chord: KeyChord)
    func currentMouseLocation() -> CGPoint
}

final class InputPoster: InputPosting {
    private var nextMouseEventNumber: Int64 = 0

    func click(at point: CGPoint, button: MouseButton) {
        let (downType, upType, cgButton): (CGEventType, CGEventType, CGMouseButton) = {
            switch button {
            case .left:
                return (.leftMouseDown, .leftMouseUp, .left)
            case .right:
                return (.rightMouseDown, .rightMouseUp, .right)
            }
        }()

        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0

        let origin = currentMouseLocation()
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)

        // Warping updates the system pointer and does not deliver a move.
        // Roblox only clicks a control it has already hovered.
        if let moved = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) {
            moved.setIntegerValueField(.mouseEventDeltaX, value: Int64((point.x - origin.x).rounded()))
            moved.setIntegerValueField(.mouseEventDeltaY, value: Int64((point.y - origin.y).rounded()))
            post(moved)
            if abs(point.x - origin.x) > 1 || abs(point.y - origin.y) > 1 {
                usleep(20_000)
            }
        }

        guard let down = CGEvent(
            mouseEventSource: source,
            mouseType: downType,
            mouseCursorPosition: point,
            mouseButton: cgButton
        ),
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: upType,
            mouseCursorPosition: point,
            mouseButton: cgButton
        ) else {
            return
        }

        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        post(down)
        // A same-instant release never shows up as a press in Roblox's frame loop.
        usleep(20_000)
        post(up)
    }

    private func post(_ event: CGEvent) {
        PostedMouseEvent.prepare(event, eventNumber: nextEventNumber())
        event.post(tap: .cghidEventTap)
    }

    private func nextEventNumber() -> Int64 {
        nextMouseEventNumber += 1
        return nextMouseEventNumber
    }

    func pressKey(_ chord: KeyChord) {
        let flags = cgEventFlags(from: chord.modifiers)

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(chord.keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(chord.keyCode), keyDown: false) else {
            return
        }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    func currentMouseLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func cgEventFlags(from modifiers: UInt) -> CGEventFlags {
        let ns = NSEvent.ModifierFlags(rawValue: modifiers)
        var flags = CGEventFlags()
        if ns.contains(.command) { flags.insert(.maskCommand) }
        if ns.contains(.option) { flags.insert(.maskAlternate) }
        if ns.contains(.control) { flags.insert(.maskControl) }
        if ns.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}

enum PostedMouseEvent {
    /// `CGEvent` mouse initializers leave the timestamp at 0. macOS 15 and later
    /// drop those events, so the pointer can still be warped while the click never arrives.
    static func prepare(_ event: CGEvent, eventNumber: Int64) {
        event.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
    }
}
