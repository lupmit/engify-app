import AppKit
import Darwin
import Foundation

struct GeminiToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let email: String
    let projectId: String

    var isExpired: Bool {
        Date().addingTimeInterval(60) >= expiresAt
    }
}

final class OAuthService {
    static let shared = OAuthService()

    private let clientId = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
    private let clientSecret = "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"
    private let redirectUri = "http://localhost:8085/oauth2callback"
    private let tokenStoreKey = "engify.gemini.token"
    private let scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile"
    ]

    private let callbackPort = 8085
    private let callbackPath = "/oauth2callback"
    private var callbackServer: SimpleHTTPServer?

    private let codeAssistEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
    private let codeAssistUserAgent = "google-api-nodejs-client/9.15.1"
    private let codeAssistApiClient = "google-cloud-sdk vscode_cloudshelleditor/0.1"
    private let codeAssistClientMetadata = "{\"ideType\":\"IDE_UNSPECIFIED\",\"platform\":\"PLATFORM_UNSPECIFIED\",\"pluginType\":\"GEMINI\"}"

    private init() {}

    func isLoggedIn() -> Bool {
        loadToken() != nil
    }

    func currentUserEmail() -> String? {
        loadToken()?.email
    }

    private func startLoginInBrowser() throws {
        let state = UUID().uuidString
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url else {
            throw OAuthError.invalidAuthorizationURL
        }

        EngifyLogger.debug("[Engify][OAuth] Opening browser for login")
        NSWorkspace.shared.open(authURL)
    }

    func getValidToken() async throws -> GeminiToken {
        if let existing = loadToken(), !existing.isExpired {
            let enriched = try await enrichTokenForCodeAssist(existing)
            if enriched.projectId != existing.projectId {
                saveToken(enriched)
            }
            return enriched
        }

        if let existing = loadToken(), !existing.refreshToken.isEmpty {
            do {
                let refreshed = try await refreshAccessToken(using: existing)
                let enriched = try await enrichTokenForCodeAssist(refreshed)
                saveToken(enriched)
                return enriched
            } catch {
                EngifyLogger.debug("[Engify][OAuth] Refresh token failed: \(error)")
            }
        }

        let fresh = try await startInteractiveLogin()
        saveToken(fresh)
        return fresh
    }

    private func startInteractiveLogin() async throws -> GeminiToken {
        EngifyLogger.debug("[Engify][OAuth] Starting OAuth flow")
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GeminiToken, Error>) in
            var timeoutTask: Task<Void, Never>?

            callbackServer = SimpleHTTPServer(port: callbackPort, path: callbackPath) { [weak self] result in
                Task {
                    timeoutTask?.cancel()
                    defer {
                        self?.callbackServer?.stop()
                        self?.callbackServer = nil
                    }

                    switch result {
                    case .success(let callbackCode):
                        do {
                            let token = try await self?.exchangeCodeForToken(code: callbackCode)
                            if let token {
                                continuation.resume(returning: token)
                            } else {
                                continuation.resume(throwing: OAuthError.tokenExchangeFailed)
                            }
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }

            do {
                try callbackServer?.start()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                    EngifyLogger.debug("[Engify][OAuth] Login timed out after 60 seconds")
                    self?.callbackServer?.stop()
                    self?.callbackServer = nil
                    continuation.resume(throwing: OAuthError.loginTimeout)
                } catch {
                    // Cancelled — login completed before timeout
                }
            }

            do {
                try self.startLoginInBrowser()
            } catch {
                timeoutTask?.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    private func refreshAccessToken(using token: GeminiToken) async throws -> GeminiToken {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(token.refreshToken.urlEncoded)",
            "client_id=\(clientId.urlEncoded)",
            "client_secret=\(clientSecret.urlEncoded)"
        ].joined(separator: "&")

        request.httpBody = body.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OAuthError.tokenRefreshFailed
        }

        let parsed = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
        return GeminiToken(
            accessToken: parsed.accessToken,
            refreshToken: parsed.refreshToken ?? token.refreshToken,
            expiresAt: Date(timeIntervalSinceNow: TimeInterval(parsed.expiresIn)),
            email: token.email,
            projectId: token.projectId
        )
    }

    private func exchangeCodeForToken(code: String) async throws -> GeminiToken {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=authorization_code",
            "code=\(code.urlEncoded)",
            "client_id=\(clientId.urlEncoded)",
            "client_secret=\(clientSecret.urlEncoded)",
            "redirect_uri=\(redirectUri.urlEncoded)"
        ].joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OAuthError.tokenExchangeFailed
        }

        let parsed = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
        let profile = try await fetchUserInfo(accessToken: parsed.accessToken)

        let initial = GeminiToken(
            accessToken: parsed.accessToken,
            refreshToken: parsed.refreshToken ?? "",
            expiresAt: Date(timeIntervalSinceNow: TimeInterval(parsed.expiresIn)),
            email: profile.email ?? "unknown",
            projectId: ""
        )

        return try await enrichTokenForCodeAssist(initial)
    }

    private func enrichTokenForCodeAssist(_ token: GeminiToken) async throws -> GeminiToken {
        let requestedProject = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let existingProject = token.projectId.trimmingCharacters(in: .whitespacesAndNewlines)

        if !existingProject.isEmpty {
            return token
        }

        do {
            if let discoveredProject = try await fetchCodeAssistProject(accessToken: token.accessToken, requestedProject: requestedProject),
               !discoveredProject.isEmpty {
                EngifyLogger.debug("[Engify][OAuth] Resolved project via loadCodeAssist: \(discoveredProject)")
                return GeminiToken(
                    accessToken: token.accessToken,
                    refreshToken: token.refreshToken,
                    expiresAt: token.expiresAt,
                    email: token.email,
                    projectId: discoveredProject
                )
            }
        } catch {
            EngifyLogger.debug("[Engify][OAuth] loadCodeAssist project resolution failed: \(error)")
        }

        if !requestedProject.isEmpty {
            EngifyLogger.debug("[Engify][OAuth] Falling back to GOOGLE_CLOUD_PROJECT: \(requestedProject)")
            return GeminiToken(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: token.expiresAt,
                email: token.email,
                projectId: requestedProject
            )
        }

        return token
    }

    private func fetchCodeAssistProject(accessToken: String, requestedProject: String) async throws -> String? {
        guard let url = URL(string: codeAssistEndpoint) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(codeAssistUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(codeAssistApiClient, forHTTPHeaderField: "X-Goog-Api-Client")
        request.setValue(codeAssistClientMetadata, forHTTPHeaderField: "Client-Metadata")

        var payload: [String: Any] = [
            "metadata": [
                "ideType": "IDE_UNSPECIFIED",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]
        ]
        if !requestedProject.isEmpty {
            payload["cloudaicompanionProject"] = requestedProject
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let id = json["cloudaicompanionProject"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let project = json["cloudaicompanionProject"] as? [String: Any],
           let id = project["id"] as? String,
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func fetchUserInfo(accessToken: String) async throws -> UserInfo {
        let url = URL(string: "https://www.googleapis.com/oauth2/v1/userinfo?alt=json")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OAuthError.userInfoFetchFailed
        }

        return try JSONDecoder().decode(UserInfo.self, from: data)
    }

    private func saveToken(_ token: GeminiToken) {
        if let encoded = try? JSONEncoder().encode(token) {
            UserDefaults.standard.set(encoded, forKey: tokenStoreKey)
        }
    }

    func clearStoredToken() {
        UserDefaults.standard.removeObject(forKey: tokenStoreKey)
    }

    func loadStoredEmail() -> String? {
        loadToken()?.email
    }

    private func loadToken() -> GeminiToken? {
        guard let data = UserDefaults.standard.data(forKey: tokenStoreKey) else {
            return nil
        }
        return try? JSONDecoder().decode(GeminiToken.self, from: data)
    }
}

enum OAuthError: Error {
    case invalidAuthorizationURL
    case callbackCancelled
    case tokenExchangeFailed
    case tokenRefreshFailed
    case userInfoFetchFailed
    case loginTimeout
}

private struct TokenExchangeResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct UserInfo: Codable {
    let email: String?
    let name: String?
}

private class SimpleHTTPServer {
    private let port: Int
    private let path: String
    private let completion: (Result<String, Error>) -> Void

    private var isRunning = false
    private var serverSocket: Int32 = -1

    init(port: Int, path: String, completion: @escaping (Result<String, Error>) -> Void) {
        self.port = port
        self.path = path
        self.completion = completion
    }

    func start() throws {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw OAuthError.callbackCancelled
        }

        var reuseAddr: Int32 = 1
        _ = setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        var bindAddr = addr
        let bindResult = withUnsafePointer(to: &bindAddr) { ptr in
            bind(serverSocket, UnsafeRawPointer(ptr).assumingMemoryBound(to: sockaddr.self), socklen_t(MemoryLayout<sockaddr_in>.size))
        }

        guard bindResult == 0 else {
            close(serverSocket)
            serverSocket = -1
            throw OAuthError.callbackCancelled
        }

        guard listen(serverSocket, 1) == 0 else {
            close(serverSocket)
            serverSocket = -1
            throw OAuthError.callbackCancelled
        }

        isRunning = true

        Task {
            await self.acceptLoop()
        }
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }

    private func acceptLoop() async {
        while isRunning {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                accept(serverSocket, UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: sockaddr.self), &clientAddrLen)
            }

            guard clientSocket >= 0 else {
                if isRunning {
                    continue
                }
                break
            }

            await handleClient(socket: clientSocket)
            break
        }

        stop()
    }

    private func handleClient(socket: Int32) async {
        defer { close(socket) }

        var buffer = [UInt8](repeating: 0, count: 2048)
        let bytesRead = read(socket, &buffer, buffer.count)
        guard bytesRead > 0 else {
            completion(.failure(OAuthError.callbackCancelled))
            return
        }

        let rawRequest = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""

        guard let callback = extractCodeAndPath(from: rawRequest) else {
            writeHTMLResponse(socket: socket, statusLine: "HTTP/1.1 400 Bad Request", body: "<html><body><h1>Invalid callback</h1></body></html>")
            completion(.failure(OAuthError.callbackCancelled))
            return
        }

        if callback.path != path {
            writeHTMLResponse(socket: socket, statusLine: "HTTP/1.1 404 Not Found", body: "<html><body><h1>Not found</h1></body></html>")
            completion(.failure(OAuthError.callbackCancelled))
            return
        }

        writeHTMLResponse(socket: socket, statusLine: "HTTP/1.1 200 OK", body: "<html><body><h1>Login successful. You can close this window.</h1></body></html>")
        completion(.success(callback.code))
    }

    private func writeHTMLResponse(socket: Int32, statusLine: String, body: String) {
        let response = """
        \(statusLine)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        response.withCString { ptr in
            _ = Darwin.write(socket, ptr, strlen(ptr))
        }
    }

    private func extractCodeAndPath(from request: String) -> (path: String, code: String)? {
        guard let firstLine = request.components(separatedBy: "\n").first else {
            return nil
        }

        let lineParts = firstLine.components(separatedBy: " ")
        guard lineParts.count >= 2 else {
            return nil
        }

        let pathAndQuery = lineParts[1]
        let querySplit = pathAndQuery.components(separatedBy: "?")
        let requestPath = querySplit[0]
        guard requestPath == path, querySplit.count > 1 else {
            return nil
        }

        let query = querySplit[1]
        let params = query.components(separatedBy: "&")
        for param in params {
            let keyValue = param.components(separatedBy: "=")
            if keyValue.count == 2, keyValue[0] == "code" {
                return (requestPath, keyValue[1].removingPercentEncoding ?? keyValue[1])
            }
        }

        return nil
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
