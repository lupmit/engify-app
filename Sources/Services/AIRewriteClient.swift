import Foundation

struct AIRewriteClient {
    private let modelFallbacks = ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"]
    private let codeAssistEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:generateContent"
    private let apiClientHeader = "google-genai-sdk/1.41.0 gl-node/v22.19.0"

    func rewrite(_ input: String, context: String? = nil, mode: String? = "polish") async throws -> String {
        try await rewrite(input, context: context, mode: mode, allowReauthRetry: true, modelIndex: 0)
    }

    private func rewrite(_ input: String, context: String?, mode: String?, allowReauthRetry: Bool, modelIndex: Int) async throws -> String {
        EngifyLogger.debug("[Engify][API] Preparing request")
        EngifyLogger.debug("[Engify][API] Input length: \(input.count)")

        let resolvedModelIndex = min(max(modelIndex, 0), modelFallbacks.count - 1)
        let modelName = modelFallbacks[resolvedModelIndex]

        let token = try await OAuthService.shared.getValidToken()

        guard let url = URL(string: codeAssistEndpoint) else {
            throw RewriteError.unknown(NSError(domain: "Engify", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini CLI endpoint URL"]))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(geminiCLIUserAgent(for: modelName), forHTTPHeaderField: "User-Agent")
        request.setValue(apiClientHeader, forHTTPHeaderField: "X-Goog-Api-Client")

        let body = GeminiCLIRequest(
            project: token.projectId,
            request: GeminiCLIInnerRequest(
                contents: [
                    GeminiContent(
                        role: "user",
                        parts: [GeminiPart(text: buildPrompt(input: input, context: context, mode: mode))]
                    )
                ],
                generationConfig: GeminiGenerationConfig(temperature: 0.2, maxOutputTokens: 1024)
            ),
            model: modelName
        )
        request.httpBody = try JSONEncoder().encode(body)

        EngifyLogger.debug("[Engify][API] Sending POST to Gemini CLI private API model \(modelName)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            EngifyLogger.debug("[Engify][API] Invalid HTTP response")
            throw RewriteError.unknown(NSError(
                domain: "Engify.API",
                code: 2001,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response from AI service."]
            ))
        }

        EngifyLogger.debug("[Engify][API] HTTP status: \(http.statusCode)")

        if !http.isOK {
            let apiError = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data)
            let message = apiError?.error.message ?? "Gemini API rejected the request."
            EngifyLogger.debug("[Engify][API] Request failed: \(message)")

            if http.statusCode == 429,
               message.localizedCaseInsensitiveContains("exhausted your capacity on this model"),
               resolvedModelIndex + 1 < modelFallbacks.count {
                let nextModel = modelFallbacks[resolvedModelIndex + 1]
                EngifyLogger.debug("[Engify][API] Capacity exhausted for \(modelName), retrying with \(nextModel)")
                return try await rewrite(input, context: context, mode: mode, allowReauthRetry: allowReauthRetry, modelIndex: resolvedModelIndex + 1)
            }

            if http.statusCode == 403,
               allowReauthRetry,
               message.localizedCaseInsensitiveContains("insufficient authentication scopes") {
                EngifyLogger.debug("[Engify][API] Token missing required scopes, forcing re-auth")
                OAuthService.shared.clearStoredToken()
                return try await rewrite(input, context: context, mode: mode, allowReauthRetry: false, modelIndex: resolvedModelIndex)
            }

            throw RewriteError.unknown(NSError(
                domain: "Engify.API",
                code: 2002,
                userInfo: [NSLocalizedDescriptionKey: message]
            ))
        }

        let parsed = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)
        let output = (parsed.response?.candidates ?? parsed.candidates)?
            .first?
            .content?
            .parts?
            .compactMap(\ .text)
            .joined(separator: "\n")

        guard let text = output?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            EngifyLogger.debug("[Engify][API] Unexpected Gemini response format or empty output")
            throw RewriteError.unknown(NSError(
                domain: "Engify.API",
                code: 2003,
                userInfo: [NSLocalizedDescriptionKey: "AI returned an empty rewrite."]
            ))
        }

        EngifyLogger.debug("[Engify][API] Success, enhanced text length: \(text.count)")
        return text
    }

    private func geminiCLIUserAgent(for modelName: String) -> String {
        "GeminiCLI/0.31.0/\(modelName) (darwin; arm64)"
    }

    private func buildPrompt(input: String, context: String?, mode: String?) -> String {
        let selectedMode = mode ?? "polish"
        let contextBlock = (context?.isEmpty == false) ? "Context:\n\(context!)\n\n" : ""

        return """
        You are an expert English writing assistant.
        Rewrite the text below according to mode "\(selectedMode)".
        Keep original meaning and key facts.
        Return only the rewritten text with no explanation.

        \(contextBlock)Input:
        \(input)
        """
    }
}

private struct GeminiCLIRequest: Codable {
    let project: String
    let request: GeminiCLIInnerRequest
    let model: String
}

private struct GeminiCLIInnerRequest: Codable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig?
}

private struct GeminiContent: Codable {
    let role: String?
    let parts: [GeminiPart]?
}

private struct GeminiPart: Codable {
    let text: String?
}

private struct GeminiGenerationConfig: Codable {
    let temperature: Double?
    let maxOutputTokens: Int?
}

private struct GeminiGenerateResponse: Codable {
    let response: GeminiCLIResponseEnvelope?
    let candidates: [GeminiCandidate]?
}

private struct GeminiCLIResponseEnvelope: Codable {
    let candidates: [GeminiCandidate]?
}

private struct GeminiCandidate: Codable {
    let content: GeminiContent?
}

private struct GeminiErrorResponse: Codable {
    let error: GeminiError
}

private struct GeminiError: Codable {
    let message: String
}

private extension HTTPURLResponse {
    var isOK: Bool { (200..<300).contains(statusCode) }
}
