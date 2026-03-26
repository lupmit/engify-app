import ApplicationServices
import CoreGraphics
import Foundation

enum AccessibilityService {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestPermissionPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func simulateCopy() {
        sendKeyboardShortcut(keyCode: 8, flags: .maskCommand)
    }

    static func simulatePaste() {
        sendKeyboardShortcut(keyCode: 9, flags: .maskCommand)
    }

    private static func sendKeyboardShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
