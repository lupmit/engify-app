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

                if viewModel.isLoggedIn {
                    Text(viewModel.loggedInEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Logout") {
                        viewModel.logout()
                    }
                } else {
                    Button("Login") {
                        viewModel.login()
                    }
                }

                Divider()

                if !viewModel.hasAccessibilityPermission {
                    Button("Request Accessibility Permission") {
                        viewModel.requestAccessibilityPermission()
                    }
                }

                Divider()

                updateView

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(12)
            .frame(width: 280)
        }
    }

    @ViewBuilder
    private var updateView: some View {
        switch viewModel.updateState {
        case .idle:
            Button("Check for Updates") {
                Task { await viewModel.checkForUpdates() }
            }
        case .checking:
            Text("Checking for updates…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .available(let version, let url):
            Button("⬆ Update to v\(version)") {
                viewModel.installUpdate(from: url)
            }
        case .downloading:
            Text("Downloading update…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error:
            VStack(alignment: .leading, spacing: 4) {
                Text("Update check failed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await viewModel.checkForUpdates() }
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
