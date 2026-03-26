import Foundation

enum RewriteError: Error {
    case permissionDenied
    case unknown(Error)

    var userFacingMessage: String {
        switch self {
        case .permissionDenied:
            return "Accessibility permission required. Open Settings and grant permission."
        case .unknown(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }
}

struct TextRewriteCoordinator {
    let client: AIRewriteClient

    func rewriteCurrentlySelectedText() async -> Result<String, RewriteError> {
        guard AccessibilityService.isTrusted() else {
            print("[Engify][Flow] Accessibility permission denied")
            return .failure(.permissionDenied)
        }

        print("[Engify][Flow] Hotkey fired — starting rewrite flow")

        // Snapshot clipboard so we can restore it after paste.
        let snapshot = ClipboardService.captureGeneralPasteboard()
        let beforeCopy = ClipboardService.readString()
        print("[Engify][Flow] Clipboard snapshot taken (before: \(beforeCopy?.prefix(40) ?? "<empty>"))")

        // Send Cmd+C to copy whatever is selected in the frontmost app.
        print("[Engify][Flow] Sending Cmd+C")
        AccessibilityService.simulateCopy()
        try? await Task.sleep(nanoseconds: 300_000_000)

        let selected = ClipboardService.readString()?.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[Engify][Flow] Clipboard after Cmd+C: \(selected?.prefix(40) ?? "<empty>")")
        guard let text = selected, !text.isEmpty, text != beforeCopy else {
            print("[Engify][Flow] Clipboard unchanged after Cmd+C — nothing selected")
            ClipboardService.restore(snapshot)
            return .success("")
        }
        print("[Engify][Flow] Got selection (length: \(text.count)): \(text.prefix(80))")

        do {
            print("[Engify][Flow] Calling AI API...")
            let rewritten = try await client.rewrite(text)
            print("[Engify][Flow] API response (length: \(rewritten.count)): \(rewritten.prefix(80))")
            ClipboardService.writeString(rewritten)
            print("[Engify][Flow] Sending Cmd+V")
            AccessibilityService.simulatePaste()
            try? await Task.sleep(nanoseconds: 150_000_000)
            ClipboardService.restore(snapshot)
            print("[Engify][Flow] Done — clipboard restored")
            return .success(rewritten)
        } catch {
            print("[Engify][Flow] Error: \(error)")
            ClipboardService.restore(snapshot)
            if let e = error as? RewriteError { return .failure(e) }
            return .failure(.unknown(error))
        }
    }
}
