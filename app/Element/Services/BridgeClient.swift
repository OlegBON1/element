import Foundation

struct HealthResponse: Codable {
    let status: String
    let version: String
}

struct StatusResponse: Codable {
    let idle: Bool
    let queue_length: Int
    let child_alive: Bool
    let version: String
}

struct InjectRequest: Codable {
    let text: String
    let priority: Bool
}

struct InjectResponse: Codable {
    let success: Bool
    let id: String?
    let position: Int?
    let error: String?
}

struct ClearResponse: Codable {
    let success: Bool
    let removed: Int
}

enum BridgeClientError: LocalizedError {
    case connectionFailed
    case invalidResponse
    case serverError(String)
    case childProcessDead

    var errorDescription: String? {
        switch self {
        case .connectionFailed: return "Cannot connect to bridge"
        case .invalidResponse: return "Invalid response from bridge"
        case .serverError(let msg): return "Bridge error: \(msg)"
        case .childProcessDead: return "Claude Code process is not running"
        }
    }
}

actor BridgeClient {
    private let baseURL: URL
    private let session: URLSession

    init(host: String = "127.0.0.1", port: Int = 9999) {
        // Force unwrap is safe here — the URL format is controlled and always valid
        self.baseURL = URL(string: "http://\(host):\(port)")
            ?? URL(string: "http://127.0.0.1:9999")!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }

    func checkHealth() async throws -> HealthResponse {
        let url = baseURL.appendingPathComponent("health")
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response)
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func getStatus() async throws -> StatusResponse {
        let url = baseURL.appendingPathComponent("status")
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response)
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }

    func inject(text: String, priority: Bool = false) async throws -> InjectResponse {
        let url = baseURL.appendingPathComponent("inject")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = InjectRequest(text: text, priority: priority)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)

        let result = try JSONDecoder().decode(InjectResponse.self, from: data)
        if !result.success, let error = result.error {
            throw BridgeClientError.serverError(error)
        }
        return result
    }

    func clearQueue() async throws -> ClearResponse {
        let url = baseURL.appendingPathComponent("queue")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)
        return try JSONDecoder().decode(ClearResponse.self, from: data)
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BridgeClientError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 503 {
                throw BridgeClientError.childProcessDead
            }
            throw BridgeClientError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }
}
