import AppKit
import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    private static let defaultStatusText = "Ready. Highlight text\nand press Command+E or Shift+Command+E."

    @Published var statusText: String = AppViewModel.defaultStatusText
    @Published var hasAccessibilityPermission: Bool = false
    @Published var hotkeyHint: String = "Command+E"
    @Published var isLoggedIn: Bool = false
    @Published var loggedInEmail: String = ""

    private let coordinator: TextRewriteCoordinator
    private let hotkeyService = GlobalHotkeyService.shared
    private var cancellables = Set<AnyCancellable>()
    private var lastHotkeyFire: Date = .distantPast
    private var isRewriteInFlight = false
    private var permissionPollingTask: Task<Void, Never>?

    init() {
        let client = AIRewriteClient()
        self.coordinator = TextRewriteCoordinator(client: client)

        hotkeyService.registerDefaultHotkey()
        bindEvents()
        requestPermissionOnLaunchIfNeeded()
        refreshLoginStatus()
    }

    func login() {
        Task { [weak self] in
            do {
                _ = try await OAuthService.shared.getValidToken()
                await MainActor.run {
                    self?.refreshLoginStatus()
                }
            } catch {
                await MainActor.run {
                    self?.refreshLoginStatus()
                }
            }
        }
    }

    func logout() {
        OAuthService.shared.clearStoredToken()
        refreshLoginStatus()
    }

    private func refreshLoginStatus() {
        loggedInEmail = OAuthService.shared.loadStoredEmail() ?? ""
        isLoggedIn = !loggedInEmail.isEmpty
        if AccessibilityService.isTrusted() {
            statusText = isLoggedIn
                ? AppViewModel.defaultStatusText
                : AppViewModel.defaultStatusText + "\n\nPlease login first."
        }
    }

    func requestAccessibilityPermission() {
        _ = AccessibilityService.requestPermissionPrompt()
        statusText = "Waiting for Accessibility permission…"
        refreshPermissionStatus()
        startPermissionPollingIfNeeded()
    }

    private func requestPermissionOnLaunchIfNeeded() {
        guard !AccessibilityService.isTrusted() else {
            refreshPermissionStatus()
            return
        }

        _ = AccessibilityService.requestPermissionPrompt()
        refreshPermissionStatus()
        startPermissionPollingIfNeeded()
    }

    private func refreshPermissionStatus() {
        hasAccessibilityPermission = AccessibilityService.isTrusted()
        if hasAccessibilityPermission {
            statusText = AppViewModel.defaultStatusText
            stopPermissionPolling()
        } else {
            statusText = "Accessibility not granted. Open menu and grant permission first."
        }
    }

    private func startPermissionPollingIfNeeded() {
        guard !hasAccessibilityPermission else { return }
        guard permissionPollingTask == nil else { return }

        permissionPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1000_000_000)
                guard let self else { return }

                await MainActor.run {
                    self.refreshPermissionStatus()
                }

                if await MainActor.run(body: { self.hasAccessibilityPermission }) {
                    return
                }
            }
        }
    }

    private func stopPermissionPolling() {
        permissionPollingTask?.cancel()
        permissionPollingTask = nil
    }

    private func bindEvents() {
        NotificationCenter.default.publisher(for: .globalHotkeyPressed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isRewriteInFlight {
                    EngifyLogger.debug("[Engify] Ignoring hotkey because rewrite is already in flight")
                    return
                }

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

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPermissionStatus()
                self?.startPermissionPollingIfNeeded()
                self?.refreshLoginStatus()
            }
            .store(in: &cancellables)
    }

    private func runRewriteFlow() async {
        guard !isRewriteInFlight else { return }
        guard isLoggedIn else {
            statusText = "Please login first."
            return
        }
        isRewriteInFlight = true

        EngifyLogger.debug("[Engify] Hotkey pressed, starting rewrite flow")
        statusText = "Processing…"
        StatusHUD.shared.showLoading()

        defer {
            isRewriteInFlight = false
            StatusHUD.shared.hide()
        }

        let result = await coordinator.rewriteCurrentlySelectedText()

        switch result {
        case .success(let updated):
            EngifyLogger.debug("[Engify] Rewrite flow succeeded")
            _ = updated
            statusText = AppViewModel.defaultStatusText
        case .failure(let error):
            EngifyLogger.debug("[Engify] Rewrite flow failed: \(error.userFacingMessage)")
            statusText = error.userFacingMessage
        }
    }

    deinit {
        permissionPollingTask?.cancel()
    }
}
