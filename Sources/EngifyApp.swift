import AppKit
import SwiftUI

@main
struct Engify: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra("Engify", systemImage: "text.bubble") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Engify")
                    .font(.headline)

                Text(viewModel.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                if !viewModel.hasAccessibilityPermission {
                    Button("Request Accessibility Permission") {
                        viewModel.requestAccessibilityPermission()
                    }
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(12)
            .frame(width: 280)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
