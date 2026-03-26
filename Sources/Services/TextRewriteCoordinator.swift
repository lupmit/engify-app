import Foundation

enum RewriteError: Error {
    case permissionDenied
    case noSelection
    case invalidEndpoint
    case remoteRejected
    case emptyResult
    case unknown(Error)

    var userFacingMessage: String {
        switch self {
        case .permissionDenied:
            return "Accessibility permission required to read/replace selected text."
        case .noSelection:
            return "No selected text found. Highlight text and try again."
        case .invalidEndpoint:
            return "Invalid AI endpoint URL."
        case .remoteRejected:
            return "AI API rejected the request."
        case .emptyResult:
            return "AI returned an empty rewrite."
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

        print("[Engify][Flow] Capturing current clipboard snapshot")
        let snapshot = ClipboardService.captureGeneralPasteboard()

        print("[Engify][Flow] Sending copy shortcut")
        AccessibilityService.simulateCopy()
        try? await Task.sleep(nanoseconds: 180_000_000)

        guard let selectedText = ClipboardService.readString()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            print("[Engify][Flow] Failed to capture selected text from clipboard")
            ClipboardService.restore(snapshot)
            return .failure(.noSelection)
        }

        print("[Engify][Flow] Selected text captured (length: \(selectedText.count))")
        print("[Engify][Flow] Selected preview: \(String(selectedText.prefix(120)))")

        do {
            let rewritten = try await client.rewrite(selectedText)
            print("[Engify][Flow] API returned rewritten text (length: \(rewritten.count))")
            ClipboardService.writeString(rewritten)

            print("[Engify][Flow] Sending paste shortcut")
            AccessibilityService.simulatePaste()
            try? await Task.sleep(nanoseconds: 120_000_000)
            print("[Engify][Flow] Paste shortcut sent")

            ClipboardService.restore(snapshot)
            print("[Engify][Flow] Clipboard restored, flow complete")
            return .success(rewritten)
        } catch {
            print("[Engify][Flow] Error during rewrite: \(error.localizedDescription)")
            ClipboardService.restore(snapshot)

            if let rewriteError = error as? RewriteError {
                return .failure(rewriteError)
            }

            return .failure(.unknown(error))
        }
    }
}
