import SwiftUI

struct RNPreviewView: View {
    let project: ProjectConfig

    @EnvironmentObject private var appState: AppState
    @StateObject private var inspectorService = RNInspectorService()
    @State private var metroConnected = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if metroConnected {
                connectedView
            } else {
                connectingView
            }
        }
        .onAppear {
            setupInspector()
        }
        .onChange(of: appState.inspectionEnabled) { _, enabled in
            if enabled {
                inspectorService.enableInspection()
            } else {
                inspectorService.disableInspection()
            }
        }
        .onDisappear {
            inspectorService.disconnect()
        }
    }

    private var connectedView: some View {
        VStack(spacing: 16) {
            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)

                Text("Connected to Metro (\(project.displayURL))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task { await reloadApp() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Reload React Native app")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Text("React Native Inspector Active")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Tap on elements in the simulator.\nSelected elements will appear in the detail panel below.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            if let error = errorMessage {
                Text(error)
                    .font(.body)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                Button("Retry Connection") {
                    setupInspector()
                }
                .buttonStyle(.bordered)
            } else {
                ProgressView("Connecting to Metro bundler...")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setupInspector() {
        errorMessage = nil

        inspectorService.configure(
            projectPath: project.path,
            onElementSelected: { element in
                appState.selectElement(element)
            }
        )

        Task {
            let metroPort = project.port ?? 8081
            let client = MetroClient(port: metroPort)

            do {
                let running = try await client.checkHealth()
                if running {
                    inspectorService.connect(metroPort: metroPort)
                    metroConnected = true
                } else {
                    errorMessage = "Metro bundler is not running on port \(metroPort)."
                }
            } catch {
                errorMessage = "Cannot connect to Metro bundler at port \(metroPort).\nMake sure your React Native app is running."
            }
        }
    }

    private func reloadApp() async {
        let metroPort = project.port ?? 8081
        let client = MetroClient(port: metroPort)
        try? await client.reloadApp()
    }
}
