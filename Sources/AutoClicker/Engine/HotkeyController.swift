import AppKit
import Carbon.HIToolbox
import Foundation

final class HotkeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var callback: (() -> Void)?

    private static let signature: OSType = OSType(UInt32(bitPattern: Int32(0x41544B59))) // 'ATKY'
    private static let hotKeyID = EventHotKeyID(signature: signature, id: 1)

    deinit {
        unregister()
    }

    func register(chord: KeyChord, onTrigger: @escaping () -> Void) {
        unregister()
        guard !chord.isEmpty else { return }
        guard chord.carbonModifiers != 0 else { return }

        callback = onTrigger

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if err == noErr, hotKeyID.id == HotkeyController.hotKeyID.id {
                    DispatchQueue.main.async {
                        controller.callback?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )

        guard status == noErr else { return }

        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(chord.keyCode),
            chord.carbonModifiers,
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if registerStatus == noErr {
            hotKeyRef = ref
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        callback = nil
    }
}
