import Foundation
import WebKit

/// Connects to React Native's built-in inspector protocol via Metro's
/// WebSocket debugger URL. Sends "inspect element" commands and receives
/// component tree + source location data.
@MainActor
final class RNInspectorService: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isInspecting = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var onElementSelected: ((ElementInfo) -> Void)?
    private var projectPath: String = ""
    private let session = URLSession.shared

    // MARK: - Configuration

    func configure(
        projectPath: String,
        onElementSelected: @escaping (ElementInfo) -> Void
    ) {
        self.projectPath = projectPath
        self.onElementSelected = onElementSelected
    }

    // MARK: - Connection

    func connect(metroPort: Int = 8081) {
        let url = URL(string: "ws://127.0.0.1:\(metroPort)/inspector/device?name=Element&app=main")!
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        receiveMessages()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        isInspecting = false
    }

    // MARK: - Inspection

    func enableInspection() {
        isInspecting = true
        sendCommand(method: "enableNetworkInspection", params: [:])
        sendCommand(method: "setInspectedElement", params: ["enabled": true])
    }

    func disableInspection() {
        isInspecting = false
        sendCommand(method: "setInspectedElement", params: ["enabled": false])
    }

    func requestElementAtPoint(x: Double, y: Double) {
        sendCommand(
            method: "selectElementAtPoint",
            params: ["x": x, "y": y]
        )
    }

    // MARK: - WebSocket Communication

    private func sendCommand(method: String, params: [String: Any]) {
        let message: [String: Any] = [
            "method": method,
            "params": params,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8)
        else { return }

        webSocketTask?.send(.string(text)) { _ in }
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveMessages()
                case .failure:
                    self?.isConnected = false
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        guard let method = json["method"] as? String else { return }

        switch method {
        case "inspectedElement":
            handleInspectedElement(json["params"] as? [String: Any] ?? [:])
        case "selectResult":
            handleSelectResult(json["params"] as? [String: Any] ?? [:])
        default:
            break
        }
    }

    private func handleInspectedElement(_ params: [String: Any]) {
        guard let source = params["source"] as? [String: Any] else { return }

        let fileName = source["fileName"] as? String ?? ""
        let lineNumber = source["lineNumber"] as? Int ?? 0
        let componentName = params["name"] as? String ?? "Unknown"

        let reader = SourceFileReader(projectPath: projectPath)
        let snippet = (try? reader.readSnippet(filePath: fileName, lineNumber: lineNumber)) ?? ""

        let tree = buildComponentTree(from: params)
        let frame = params["frame"] as? [String: Double] ?? [:]

        let element = ElementInfo(
            id: UUID(),
            platform: .reactNative,
            componentName: componentName,
            filePath: fileName,
            lineNumber: lineNumber,
            columnNumber: source["columnNumber"] as? Int,
            codeSnippet: snippet,
            componentTree: tree,
            elementRect: ElementInfo.ElementRect(
                x: frame["x"] ?? 0,
                y: frame["y"] ?? 0,
                width: frame["width"] ?? 0,
                height: frame["height"] ?? 0
            ),
            tagName: params["type"] as? String ?? "View",
            textContent: params["text"] as? String,
            timestamp: Date(),
            accessibilityIdentifier: params["testID"] as? String ?? "",
            childrenSummary: []
        )

        onElementSelected?(element)
    }

    private func handleSelectResult(_ params: [String: Any]) {
        handleInspectedElement(params)
    }

    private func buildComponentTree(from params: [String: Any]) -> [String] {
        guard let hierarchy = params["hierarchy"] as? [[String: Any]] else {
            if let name = params["name"] as? String {
                return [name]
            }
            return []
        }

        return hierarchy.compactMap { $0["name"] as? String }
    }
}
