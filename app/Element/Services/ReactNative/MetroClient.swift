import Foundation

enum MetroClientError: LocalizedError {
    case connectionFailed
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed: return "Cannot connect to Metro bundler"
        case .invalidResponse: return "Invalid response from Metro"
        case .serverError(let msg): return "Metro error: \(msg)"
        }
    }
}

struct MetroDeviceInfo: Codable {
    let id: String
    let title: String
    let type: String
    let webSocketDebuggerUrl: String?
}

actor MetroClient {
    private let host: String
    private let port: Int
    private let session: URLSession

    init(host: String = "127.0.0.1", port: Int = 8081) {
        self.host = host
        self.port = port

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }

    var baseURL: URL {
        // Force unwrap is safe here — the URL format is controlled and always valid
        URL(string: "http://\(host):\(port)")
            ?? URL(string: "http://127.0.0.1:8081")!
    }

    func checkHealth() async throws -> Bool {
        let url = baseURL.appendingPathComponent("status")
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response)
        let status = String(data: data, encoding: .utf8) ?? ""
        return status.contains("packager-status:running")
    }

    func getDevices() async throws -> [MetroDeviceInfo] {
        let url = baseURL.appendingPathComponent("json")
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response)
        return try JSONDecoder().decode([MetroDeviceInfo].self, from: data)
    }

    func openDevMenu() async throws {
        let url = baseURL.appendingPathComponent("open-debugger")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try validateHTTPResponse(response)
    }

    func reloadApp() async throws {
        let url = baseURL.appendingPathComponent("reload")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try validateHTTPResponse(response)
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MetroClientError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MetroClientError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }
}
