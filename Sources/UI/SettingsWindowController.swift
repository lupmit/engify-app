import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {}

    func show(viewModel: AppViewModel) {
        if window == nil {
            let content = SettingsView(viewModel: viewModel)
                .frame(width: 520, height: 360)
                .padding(16)

            let hosting = NSHostingView(rootView: content)
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "Engify Settings"
            newWindow.contentView = hosting
            newWindow.center()
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            window = newWindow
        }

        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Keep the window instance for fast reopen and preserved field state.
    }
}
