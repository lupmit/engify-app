import AppKit
import Foundation

struct ClipboardSnapshot {
    let string: String?
}

enum ClipboardService {
    static func captureGeneralPasteboard() -> ClipboardSnapshot {
        ClipboardSnapshot(string: readString())
    }

    static func restore(_ snapshot: ClipboardSnapshot) {
        if let value = snapshot.string {
            writeString(value)
        }
    }

    static func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func writeString(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
