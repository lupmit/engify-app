import AppKit
import Foundation

struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
}

enum ClipboardService {
    static func captureGeneralPasteboard() -> ClipboardSnapshot {
        let pasteboard = NSPasteboard.general
        let serialized = (pasteboard.pasteboardItems ?? []).map { item in
            var map: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    map[type] = data
                }
            }
            return map
        }

        return ClipboardSnapshot(items: serialized)
    }

    static func restore(_ snapshot: ClipboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let items = snapshot.items.map { dataMap -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dataMap {
                item.setData(data, forType: type)
            }
            return item
        }

        if !items.isEmpty {
            pasteboard.writeObjects(items)
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
