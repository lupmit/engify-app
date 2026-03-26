import Carbon
import Foundation

final class GlobalHotkeyService {
    static let shared = GlobalHotkeyService()

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    private init() {}

    func registerDefaultHotkey() {
        unregister()

        // Register two hotkeys with separate IDs:
        //   id: 1 → Command+E
        //   id: 2 → Shift+Command+E
        let hotkeys: [(id: UInt32, modifiers: UInt32)] = [
            (1, UInt32(cmdKey)),
            (2, UInt32(cmdKey | shiftKey)),
        ]
        let keyCode: UInt32 = 14 // E key

        for hotkey in hotkeys {
            var ref: EventHotKeyRef?
            let hotkeyID = EventHotKeyID(signature: OSType(0x454E4746), id: hotkey.id)
            let status = RegisterEventHotKey(keyCode, hotkey.modifiers, hotkeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
            }
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
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        unregister()
    }
}
