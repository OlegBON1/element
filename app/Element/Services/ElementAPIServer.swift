import Foundation
import Network

/// Lightweight HTTP server on localhost:7749 for MCP integration.
/// Exposes Element app state so the MCP server can query it.
@MainActor
final class ElementAPIServer: ObservableObject {
    @Published private(set) var isRunning = false

    private var listener: NWListener?
    private weak var appState: AppState?

    static let port: UInt16 = 7749

    func start(appState: AppState) {
        self.appState = appState

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            guard let listenPort = NWEndpoint.Port(rawValue: Self.port) else {
                NSLog("[ElementAPI] Invalid port: \(Self.port)")
                return
            }
            listener = try NWListener(using: params, on: listenPort)
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        NSLog("[ElementAPI] Server listening on localhost:\(Self.port)")
                    case .failed(let error):
                        self?.isRunning = false
                        NSLog("[ElementAPI] Server failed: \(error)")
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }

            listener?.start(queue: .global(qos: .userInitiated))
        } catch {
            NSLog("[ElementAPI] Failed to create listener: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let error {
                NSLog("[ElementAPI] Receive error: \(error)")
                connection.cancel()
                return
            }

            guard let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            Task { @MainActor in
                self?.routeRequest(request, connection: connection)
            }
        }
    }

    // MARK: - Routing

    @MainActor
    private func routeRequest(_ raw: String, connection: NWConnection) {
        let (method, path) = parseRequestLine(raw)

        let responseJSON: String
        switch (method, path) {
        case ("GET", "/health"):
            responseJSON = healthResponse()
        case ("GET", "/selection"):
            responseJSON = selectionResponse()
        case ("GET", "/context"):
            responseJSON = contextResponse()
        case ("GET", "/projects"):
            responseJSON = projectsResponse()
        default:
            sendResponse(connection: connection, status: 404, body: #"{"error":"not_found"}"#)
            return
        }

        sendResponse(connection: connection, status: 200, body: responseJSON)
    }

    // MARK: - Route Handlers

    @MainActor
    private func healthResponse() -> String {
        let running = isRunning
        return #"{"status":"ok","running":\#(running),"version":"1.0.0"}"#
    }

    @MainActor
    private func selectionResponse() -> String {
        guard let element = appState?.selectedElement else {
            return #"{"selected":false}"#
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(SelectionPayload(element: element)),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"selected":false,"error":"encoding_failed"}"#
        }
        return json
    }

    @MainActor
    private func contextResponse() -> String {
        guard let state = appState else {
            return #"{"error":"no_state"}"#
        }

        let prompt = state.renderedPrompt ?? ""
        let projectName = state.selectedProject?.name ?? ""
        let projectPath = state.selectedProject?.path ?? ""
        let platform = state.selectedProject?.platform.rawValue ?? ""
        let hasElement = state.selectedElement != nil
        let inspecting = state.inspectionEnabled

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let context = ContextPayload(
            hasSelectedElement: hasElement,
            renderedPrompt: prompt,
            projectName: projectName,
            projectPath: projectPath,
            platform: platform,
            inspectionEnabled: inspecting,
            element: hasElement ? state.selectedElement : nil
        )

        guard let data = try? encoder.encode(context),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"error":"encoding_failed"}"#
        }
        return json
    }

    @MainActor
    private func projectsResponse() -> String {
        guard let state = appState else {
            return #"{"projects":[]}"#
        }

        let projects = state.projects.map { p in
            ProjectPayload(
                id: p.id.uuidString,
                name: p.name,
                path: p.path,
                platform: p.platform.rawValue,
                url: p.url
            )
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(ProjectsPayload(projects: projects)),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"projects":[]}"#
        }
        return json
    }

    // MARK: - HTTP Helpers

    private func parseRequestLine(_ raw: String) -> (String, String) {
        let firstLine = raw.split(separator: "\r\n").first ?? raw.split(separator: "\n").first ?? Substring(raw)
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return ("GET", "/") }
        return (String(parts[0]), String(parts[1]))
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: http://localhost\r
        Connection: close\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - API Payloads

private struct SelectionPayload: Encodable {
    let selected: Bool = true
    let element: ElementSummary

    init(element: ElementInfo) {
        self.element = ElementSummary(element: element)
    }
}

private struct ElementSummary: Encodable {
    let platform: String
    let componentName: String
    let tagName: String
    let textContent: String
    let filePath: String
    let lineNumber: Int
    let columnNumber: Int?
    let codeSnippet: String
    let componentTree: [String]
    let frame: FrameSummary
    let accessibilityIdentifier: String
    let childrenSummary: [String]

    init(element: ElementInfo) {
        self.platform = element.platform.rawValue
        self.componentName = element.componentName
        self.tagName = element.tagName
        self.textContent = element.textContent ?? ""
        self.filePath = element.filePath
        self.lineNumber = element.lineNumber
        self.columnNumber = element.columnNumber
        self.codeSnippet = element.codeSnippet
        self.componentTree = element.componentTree
        self.frame = FrameSummary(
            x: element.elementRect.x,
            y: element.elementRect.y,
            width: element.elementRect.width,
            height: element.elementRect.height
        )
        self.accessibilityIdentifier = element.accessibilityIdentifier
        self.childrenSummary = element.childrenSummary
    }
}

private struct FrameSummary: Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private struct ContextPayload: Encodable {
    let hasSelectedElement: Bool
    let renderedPrompt: String
    let projectName: String
    let projectPath: String
    let platform: String
    let inspectionEnabled: Bool
    let element: ElementInfo?
}

private struct ProjectPayload: Encodable {
    let id: String
    let name: String
    let path: String
    let platform: String
    let url: String
}

private struct ProjectsPayload: Encodable {
    let projects: [ProjectPayload]
}
