import Carbon
import Foundation

final class GlobalHotkeyService {
    static let shared = GlobalHotkeyService()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init() {}

    func registerDefaultHotkey() {
        unregister()

        let hotkeyID = EventHotKeyID(signature: OSType(0x454E4746), id: 1) // ENGF
        let modifiers = UInt32(controlKey | shiftKey)
        let keyCode: UInt32 = 14 // E key

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if result == noErr {
                    NotificationCenter.default.post(name: .globalHotkeyPressed, object: nil)
                }

                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        unregister()
    }
}
