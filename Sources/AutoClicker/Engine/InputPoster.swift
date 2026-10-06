import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

protocol InputPosting: AnyObject {
    func click(at point: CGPoint, button: MouseButton)
    func pressKey(_ chord: KeyChord)
    func currentMouseLocation() -> CGPoint
}

final class InputPoster: InputPosting {
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
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)

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
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
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
