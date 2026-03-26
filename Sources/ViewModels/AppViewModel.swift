import AppKit
import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var statusText: String = "Ready. Highlight text anywhere and press Control+Shift+E."
    @Published var hotkeyHint: String = "Control+Shift+E"

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

    func openSettings() {
        SettingsWindowController.shared.show(viewModel: self)
    }

    private func refreshPermissionStatus() {
        if AccessibilityService.isTrusted() {
            statusText = "Accessibility granted. Ready on \(hotkeyHint)."
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
        statusText = "Processing selected text..."
        let result = await coordinator.rewriteCurrentlySelectedText()

        switch result {
        case .success(let updated):
            print("[Engify] Rewrite flow succeeded")
            statusText = "Updated text: \(updated.prefix(80))"
        case .failure(let error):
            print("[Engify] Rewrite flow failed: \(error.userFacingMessage)")
            statusText = error.userFacingMessage
        }
    }
}
