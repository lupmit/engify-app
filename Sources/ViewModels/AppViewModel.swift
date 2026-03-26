import AppKit
import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    private static let defaultStatusText = "Ready. Highlight text\nand press Command+E or Shift+Command+E."

    @Published var statusText: String = AppViewModel.defaultStatusText
    @Published var hasAccessibilityPermission: Bool = false
    @Published var hotkeyHint: String = "Command+E"

    private let coordinator: TextRewriteCoordinator
    private let hotkeyService = GlobalHotkeyService.shared
    private var cancellables = Set<AnyCancellable>()
    private var lastHotkeyFire: Date = .distantPast

    init() {
        let client = AIRewriteClient()
        self.coordinator = TextRewriteCoordinator(client: client)

        hotkeyService.registerDefaultHotkey()
        bindEvents()
        refreshPermissionStatus()
    }

    func requestAccessibilityPermission() {
        _ = AccessibilityService.requestPermissionPrompt()
        refreshPermissionStatus()
    }

    private func refreshPermissionStatus() {
        hasAccessibilityPermission = AccessibilityService.isTrusted()
        if hasAccessibilityPermission {
            statusText = AppViewModel.defaultStatusText
        } else {
            statusText = "Accessibility not granted. Open menu and grant permission first."
        }
    }

    private func bindEvents() {
        NotificationCenter.default.publisher(for: .globalHotkeyPressed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let now = Date()
                if now.timeIntervalSince(self.lastHotkeyFire) < 0.8 {
                    return
                }
                self.lastHotkeyFire = now

                Task { [weak self] in
                    await self?.runRewriteFlow()
                }
            }
            .store(in: &cancellables)
    }

    private func runRewriteFlow() async {
        print("[Engify] Hotkey pressed, starting rewrite flow")
        statusText = "Processing…"
        StatusHUD.shared.showLoading()

        let result = await coordinator.rewriteCurrentlySelectedText()
        StatusHUD.shared.hide()

        switch result {
        case .success(let updated):
            print("[Engify] Rewrite flow succeeded")
            _ = updated
            statusText = AppViewModel.defaultStatusText
        case .failure(let error):
            print("[Engify] Rewrite flow failed: \(error.userFacingMessage)")
            statusText = error.userFacingMessage
        }
    }
}
