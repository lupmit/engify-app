import AppKit
import Foundation

struct UpdateInfo {
    let latestVersion: String
    let downloadURL: URL
}

enum UpdateService {
    private static let releasesURL = URL(string: "https://api.github.com/repos/lupmit/engify-app/releases/latest")!

    // MARK: - Current version

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Returns true when the app is running from a dev build (swift run / .build/).
    private static var isDevBuild: Bool {
        Bundle.main.bundlePath.contains("/.build/")
    }

    // MARK: - Check

    /// Fetches the latest GitHub release and returns update info if a newer version is available.
    /// Returns nil when already up to date or running in dev mode.
    static func checkForUpdate() async throws -> UpdateInfo? {
        guard !isDevBuild else {
            EngifyLogger.debug("[Engify][Update] Dev build detected — skipping update check")
            return nil
        }

        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Engify/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.networkError("GitHub API returned a non-200 response")
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let latestVersion = release.tagName.trimmingCharacters(in: .init(charactersIn: "v"))

        EngifyLogger.debug("[Engify][Update] Latest: \(latestVersion), current: \(currentVersion)")

        guard isNewer(latestVersion, than: currentVersion) else {
            EngifyLogger.debug("[Engify][Update] Already up to date")
            return nil
        }

        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let downloadURL = URL(string: asset.browserDownloadURL) else {
            throw UpdateError.noZipAsset
        }

        return UpdateInfo(latestVersion: latestVersion, downloadURL: downloadURL)
    }

    // MARK: - Download + Install

    /// Downloads the .zip, extracts Engify.app into a temp location, then launches a
    /// detached shell script that replaces the running app after it quits.
    static func downloadAndInstall(from url: URL) async throws {
        EngifyLogger.debug("[Engify][Update] Downloading from \(url)")

        let (tmpZip, _) = try await URLSession.shared.download(from: url)

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("engify-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let destZip = tmpDir.appendingPathComponent("Engify.zip")
        try FileManager.default.moveItem(at: tmpZip, to: destZip)

        // Unzip using ditto to preserve macOS metadata / symlinks.
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", destZip.path, tmpDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw UpdateError.extractFailed
        }

        let newApp = tmpDir.appendingPathComponent("Engify.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else {
            throw UpdateError.extractFailed
        }

        let installPath = Bundle.main.bundleURL.path
        EngifyLogger.debug("[Engify][Update] Installing to \(installPath)")

        // Write a self-contained shell script that runs after the app exits.
        let scriptPath = tmpDir.appendingPathComponent("apply_update.sh").path
        let script = """
        #!/bin/zsh
        sleep 1.5
        xattr -cr \(shellEscape(newApp.path))
        rm -rf \(shellEscape(installPath))
        cp -R \(shellEscape(newApp.path)) \(shellEscape(installPath))
        open \(shellEscape(installPath))
        rm -- "$0"
        """
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/zsh")
        launcher.arguments = [scriptPath]
        try launcher.run()
        // Intentionally not waiting — the script runs after we quit.

        EngifyLogger.debug("[Engify][Update] Update script launched, quitting app")
        await MainActor.run { NSApplication.shared.terminate(nil) }
    }

    // MARK: - Helpers

    private static func isNewer(_ candidate: String, than current: String) -> Bool {
        semverTuple(candidate) > semverTuple(current)
    }

    private static func semverTuple(_ version: String) -> (Int, Int, Int) {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        return (parts.indices.contains(0) ? parts[0] : 0,
                parts.indices.contains(1) ? parts[1] : 0,
                parts.indices.contains(2) ? parts[2] : 0)
    }

    /// Wraps a path in single-quotes, escaping any embedded single-quotes.
    private static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case networkError(String)
    case noZipAsset
    case extractFailed

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "Update check failed: \(msg)"
        case .noZipAsset: return "No .zip asset found in the latest release."
        case .extractFailed: return "Failed to extract the update package."
        }
    }
}

// MARK: - GitHub API models

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
