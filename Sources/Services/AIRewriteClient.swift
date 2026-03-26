import Foundation

struct AIRewriteClient {
    private let workerURL = "https://engify.lupmit.workers.dev"

    func rewrite(_ input: String, context: String? = nil, mode: String? = "polish") async throws -> String {
        print("[Engify][API] Preparing request")
        print("[Engify][API] Input length: \(input.count)")

        guard let url = URL(string: workerURL) else {
            throw RewriteError.unknown(NSError(domain: "Engify", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint URL"]))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = WorkerRequest(text: input, context: context, mode: mode)
        request.httpBody = try JSONEncoder().encode(body)

        print("[Engify][API] Sending POST to \(workerURL)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            print("[Engify][API] Invalid HTTP response")
            throw RewriteError.remoteRejected
        }

        print("[Engify][API] HTTP status: \(http.statusCode)")

        let parsed = try JSONDecoder().decode(WorkerResponse.self, from: data)

        if !http.isOK {
            print("[Engify][API] Request failed with response error: \(parsed.error ?? "unknown")")
            throw RewriteError.remoteRejected
        }

        guard parsed.success,
              let text = parsed.enhancedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            print("[Engify][API] Unexpected response format or empty enhancedText")
            throw RewriteError.emptyResult
        }

        print("[Engify][API] Success, enhanced text length: \(text.count)")
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
