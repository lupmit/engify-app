import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Engify Settings")
                .font(.title2)

            Text("Global hotkey: \(viewModel.hotkeyHint)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("API endpoint is hardcoded to:")
                .font(.callout)
            Text("https://engify.lupmit.workers.dev")
                .font(.footnote)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Debug logs are printed to console when hotkey runs: capture text, API call result, and replace status.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Request Accessibility") {
                    viewModel.requestAccessibilityPermission()
                }
            }

            Spacer()
        }
    }
}
