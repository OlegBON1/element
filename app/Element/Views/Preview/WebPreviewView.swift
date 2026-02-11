import AppKit
import SwiftUI
import WebKit

struct WebPreviewView: View {
    let project: ProjectConfig

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var devServerManager: DevServerManager
    @StateObject private var inspectorService = WebInspectorService()
    @StateObject private var webState = WebViewState()
    @State private var isStartingServer = false

    var body: some View {
        Group {
            if project.previewURL == nil {
                noURLPlaceholder
            } else {
                webContent
            }
        }
        .onChange(of: appState.inspectionEnabled) { _, enabled in
            if enabled {
                inspectorService.injectSDK()
                inspectorService.enableInspection()
            } else {
                inspectorService.disableInspection()
            }
        }
    }

    // MARK: - Web Content (single WKWebView with overlays)

    private var webContent: some View {
        ZStack {
            // The WKWebView is always present — never recreated
            WebViewRepresentable(
                project: project,
                inspectorService: inspectorService,
                webState: webState,
                onElementSelected: { element in
                    appState.selectElement(element)
                }
            )

            // Overlay: loading spinner
            if case .loading = webState.loadingPhase {
                loadingOverlay
            }

            // Overlay: error view (replaces content visually)
            if case .failed(let error) = webState.loadingPhase {
                errorView(error)
            }

            // Toolbar (top-right)
            if case .loaded = webState.loadingPhase {
                VStack {
                    HStack {
                        Spacer()
                        toolbar
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text("Loading \(project.displayURL)…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Error View

    private func errorView(_ error: WebLoadError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: error.iconName)
                .font(.system(size: 40))
                .foregroundStyle(error.iconColor)

            Text(error.title)
                .font(.title3)
                .fontWeight(.medium)

            Text(error.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if !error.suggestion.isEmpty {
                Text(error.suggestion)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                    .padding(.top, 4)
            }

            HStack(spacing: 12) {
                Button {
                    retryLoad()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                }
                .buttonStyle(.borderedProminent)

                if error.isServerError {
                    serverActionButton
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - No URL Placeholder

    private var noURLPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No URL configured")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Set a preview URL in project settings")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            Button {
                retryLoad()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Reload page")

            Button {
                inspectorService.injectSDK()
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Reload Element SDK")
        }
        .padding(8)
    }

    // MARK: - Server Action Button

    @ViewBuilder
    private var serverActionButton: some View {
        if isStartingServer {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Starting server…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        } else if devServerManager.isRunning(projectID: project.id) {
            Button {
                stopDevServer()
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop Server")
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
        } else {
            Button {
                startDevServer()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Server")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions

    private func retryLoad() {
        webState.loadingPhase = .loading
        webState.requestReload()
    }

    private func startDevServer() {
        isStartingServer = true
        devServerManager.start(project: project)

        Task {
            try? await Task.sleep(for: .seconds(3))
            isStartingServer = false
            retryLoad()
        }
    }

    private func stopDevServer() {
        devServerManager.stop(projectID: project.id)
        isStartingServer = false
    }
}

// MARK: - Web Load Error

struct WebLoadError: Equatable {
    let title: String
    let message: String
    let suggestion: String
    let isServerError: Bool

    var iconName: String {
        isServerError ? "server.rack" : "exclamationmark.triangle"
    }

    var iconColor: Color {
        isServerError ? .orange : .red
    }

    static func serverNotRunning(url: String) -> WebLoadError {
        WebLoadError(
            title: "Cannot Connect",
            message: "Could not reach \(url). Make sure your development server is running.",
            suggestion: "Start your dev server (e.g., npm run dev) and try again.",
            isServerError: true
        )
    }

    static func loadFailed(description: String) -> WebLoadError {
        WebLoadError(
            title: "Page Failed to Load",
            message: description,
            suggestion: "Check your URL and network connection.",
            isServerError: false
        )
    }

    static func invalidURL(_ url: String) -> WebLoadError {
        WebLoadError(
            title: "Invalid URL",
            message: "\"\(url)\" is not a valid URL.",
            suggestion: "Check your project settings and enter a valid URL (e.g., http://localhost:3000).",
            isServerError: false
        )
    }
}

// MARK: - Web View State

enum WebLoadingPhase: Equatable {
    case loading
    case loaded
    case failed(WebLoadError)
}

@MainActor
final class WebViewState: ObservableObject {
    @Published var loadingPhase: WebLoadingPhase = .loading
    @Published private(set) var reloadToken = UUID()

    func requestReload() {
        reloadToken = UUID()
    }
}

// MARK: - WKWebView Wrapper

private struct WebViewRepresentable: NSViewRepresentable {
    let project: ProjectConfig
    let inspectorService: WebInspectorService
    @ObservedObject var webState: WebViewState
    let onElementSelected: (ElementInfo) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(webState: webState)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Custom user agent to avoid bot-detection issues
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Element/1.0"

        inspectorService.configure(
            webView: webView,
            projectPath: project.path,
            onElementSelected: onElementSelected
        )

        loadURL(in: webView)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Detect reload requests via token change
        if context.coordinator.lastReloadToken != webState.reloadToken {
            context.coordinator.lastReloadToken = webState.reloadToken
            loadURL(in: webView)
        }
    }

    private func loadURL(in webView: WKWebView) {
        guard let url = project.previewURL else {
            Task { @MainActor in
                webState.loadingPhase = .failed(.invalidURL(project.url))
            }
            return
        }

        Task { @MainActor in
            webState.loadingPhase = .loading
        }

        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        webView.load(request)
    }

    // MARK: - Navigation Delegate Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        let webState: WebViewState
        var lastReloadToken: UUID
        weak var webView: WKWebView?

        init(webState: WebViewState) {
            self.webState = webState
            self.lastReloadToken = webState.reloadToken
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                self.webState.loadingPhase = .loading
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.webState.loadingPhase = .loaded
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.handleNavigationError(error, url: webView.url?.absoluteString ?? "")
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.handleNavigationError(error, url: webView.url?.absoluteString ?? "")
            }
        }

        // Allow insecure HTTP for localhost dev servers
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(.allow)
        }

        // Handle SSL/TLS challenges for localhost
        func webView(
            _ webView: WKWebView,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            // Trust localhost certificates for dev servers
            if let host = challenge.protectionSpace.host.lowercased() as String?,
               host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0" {
                if let trust = challenge.protectionSpace.serverTrust {
                    completionHandler(.useCredential, URLCredential(trust: trust))
                    return
                }
            }
            completionHandler(.performDefaultHandling, nil)
        }

        @MainActor
        private func handleNavigationError(_ error: Error, url: String) {
            let nsError = error as NSError

            // Cancelled navigations are not real errors (e.g. rapid reload)
            if nsError.code == NSURLErrorCancelled {
                return
            }

            // Connection refused / cannot connect = server not running
            let connectionErrorCodes = [
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorTimedOut,
                NSURLErrorSecureConnectionFailed
            ]

            if connectionErrorCodes.contains(nsError.code) {
                let failedURL = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String ?? url
                webState.loadingPhase = .failed(.serverNotRunning(url: failedURL))
            } else {
                webState.loadingPhase = .failed(.loadFailed(description: error.localizedDescription))
            }
        }
    }
}
