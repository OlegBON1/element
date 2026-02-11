import Foundation
import WebKit

@MainActor
final class WebInspectorService: ObservableObject {
    @Published private(set) var isInspecting = false

    private var webView: WKWebView?
    private var messageHandler: WebMessageHandler?
    private var onElementSelected: ((ElementInfo) -> Void)?
    private var projectPath: String = ""

    func configure(
        webView: WKWebView,
        projectPath: String,
        onElementSelected: @escaping (ElementInfo) -> Void
    ) {
        self.webView = webView
        self.projectPath = projectPath
        self.onElementSelected = onElementSelected

        setupMessageHandler(webView: webView)
    }

    func injectSDK() {
        guard let webView else { return }

        guard let sdkURL = Bundle.main.url(forResource: "element-sdk", withExtension: "js"),
              let sdkSource = try? String(contentsOf: sdkURL, encoding: .utf8)
        else {
            NSLog("[Element] element-sdk.js not found in app bundle. Ensure it is included in Resources.")
            return
        }

        webView.evaluateJavaScript(sdkSource)
    }

    func enableInspection() {
        isInspecting = true
        webView?.evaluateJavaScript("ElementSDK.enable()")
    }

    func disableInspection() {
        isInspecting = false
        webView?.evaluateJavaScript("ElementSDK.disable()")
    }

    func toggleInspection() {
        if isInspecting {
            disableInspection()
        } else {
            enableInspection()
        }
    }

    private func setupMessageHandler(webView: WKWebView) {
        let handler = WebMessageHandler(
            onElementSelected: { [weak self] payload in
                Task { @MainActor in
                    self?.handleElementPayload(payload)
                }
            },
            onNotification: { type, message in
                // Could log or surface notifications in future
                _ = (type, message)
            }
        )
        messageHandler = handler

        webView.configuration.userContentController.add(handler, name: "elementBridge")
    }

    private func handleElementPayload(_ payload: SDKElementPayload) {
        let reader = SourceFileReader(projectPath: projectPath)

        var snippet = ""
        if !payload.filePath.isEmpty, payload.lineNumber > 0 {
            snippet = (try? reader.readSnippet(
                filePath: payload.filePath,
                lineNumber: payload.lineNumber
            )) ?? ""
        }

        let element = ElementInfo(
            id: UUID(),
            platform: .web,
            componentName: payload.componentName,
            filePath: payload.filePath,
            lineNumber: payload.lineNumber,
            columnNumber: payload.columnNumber,
            codeSnippet: snippet,
            componentTree: payload.componentTree,
            elementRect: ElementInfo.ElementRect(
                x: payload.elementRect.x,
                y: payload.elementRect.y,
                width: payload.elementRect.width,
                height: payload.elementRect.height
            ),
            tagName: payload.tagName,
            textContent: payload.textContent,
            timestamp: Date(),
            accessibilityIdentifier: "",
            childrenSummary: []
        )

        onElementSelected?(element)
    }
}
