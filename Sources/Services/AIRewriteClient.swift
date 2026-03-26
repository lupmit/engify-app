import Foundation

struct AIRewriteClient {
    private let workerURL = "https://engify.lupmit.workers.dev"

    func rewrite(_ input: String, context: String? = nil, mode: String? = "polish") async throws -> String {
        EngifyLogger.debug("[Engify][API] Preparing request")
        EngifyLogger.debug("[Engify][API] Input length: \(input.count)")

        guard let url = URL(string: workerURL) else {
            throw RewriteError.unknown(NSError(domain: "Engify", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint URL"]))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = WorkerRequest(text: input, context: context, mode: mode)
        request.httpBody = try JSONEncoder().encode(body)

        EngifyLogger.debug("[Engify][API] Sending POST to \(workerURL)")
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

        let parsed = try JSONDecoder().decode(WorkerResponse.self, from: data)

        if !http.isOK {
            EngifyLogger.debug("[Engify][API] Request failed with response error: \(parsed.error ?? "unknown")")
            throw RewriteError.unknown(NSError(
                domain: "Engify.API",
                code: 2002,
                userInfo: [NSLocalizedDescriptionKey: parsed.error ?? "AI API rejected the request."]
            ))
        }

        guard parsed.success,
              let text = parsed.enhancedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            EngifyLogger.debug("[Engify][API] Unexpected response format or empty enhancedText")
            throw RewriteError.unknown(NSError(
                domain: "Engify.API",
                code: 2003,
                userInfo: [NSLocalizedDescriptionKey: "AI returned an empty rewrite."]
            ))
        }

        EngifyLogger.debug("[Engify][API] Success, enhanced text length: \(text.count)")
        return text
    }
}

private struct WorkerRequest: Codable {
    let text: String
    let context: String?
    let mode: String?
}

private struct WorkerResponse: Codable {
    let success: Bool
    let enhancedText: String?
    let error: String?
}

private extension HTTPURLResponse {
    var isOK: Bool { (200..<300).contains(statusCode) }
}
