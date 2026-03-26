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
            EngifyLogger.debug("[Engify][Flow] Accessibility permission denied")
            return .failure(.permissionDenied)
        }

        EngifyLogger.debug("[Engify][Flow] Hotkey fired — starting rewrite flow")

        // Snapshot clipboard so we can restore it after paste.
        let snapshot = ClipboardService.captureGeneralPasteboard()
        let beforeCopy = ClipboardService.readString()
        EngifyLogger.debug("[Engify][Flow] Clipboard snapshot taken (before: \(beforeCopy?.prefix(40) ?? "<empty>"))")

        // Send Cmd+C to copy whatever is selected in the frontmost app.
        EngifyLogger.debug("[Engify][Flow] Sending Cmd+C")
        AccessibilityService.simulateCopy()

        try? await Task.sleep(nanoseconds: 120_000_000)
        let selected = ClipboardService.readString()?.trimmingCharacters(in: .whitespacesAndNewlines)
        EngifyLogger.debug("[Engify][Flow] Clipboard after Cmd+C: \(selected?.prefix(40) ?? "<empty>")")
        guard let text = selected, !text.isEmpty else {
            EngifyLogger.debug("[Engify][Flow] Clipboard empty after Cmd+C — nothing selected")
            ClipboardService.restore(snapshot)
            return .success("")
        }
        EngifyLogger.debug("[Engify][Flow] Got selection (length: \(text.count))")

        do {
            EngifyLogger.debug("[Engify][Flow] Calling AI API...")
            let rewritten = try await client.rewrite(text)
            EngifyLogger.debug("[Engify][Flow] API response length: \(rewritten.count)")
            ClipboardService.writeString(rewritten)
            EngifyLogger.debug("[Engify][Flow] Sending Cmd+V")
            AccessibilityService.simulatePaste()
            try? await Task.sleep(nanoseconds: 150_000_000)
            ClipboardService.restore(snapshot)
            EngifyLogger.debug("[Engify][Flow] Done — clipboard restored")
            return .success(rewritten)
        } catch {
            EngifyLogger.debug("[Engify][Flow] Error: \(error)")
            ClipboardService.restore(snapshot)
            if let e = error as? RewriteError { return .failure(e) }
            return .failure(.unknown(error))
        }
    }
}
