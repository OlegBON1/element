import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var claudeSession: ClaudeCodeSession
    @EnvironmentObject private var devServerManager: DevServerManager

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            if appState.selectedProject != nil {
                DetailContentView()
            } else {
                EmptyProjectView()
            }
        }
        .toolbar(removing: .sidebarToggle)
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarContent
            }
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        ClaudeSessionStatusIndicator(status: claudeSession.status)

        if let project = appState.selectedProject,
           project.platform == .web {
            DevServerToolbarButton(
                isRunning: devServerManager.isRunning(projectID: project.id),
                onStart: { devServerManager.start(project: project) },
                onStop: { devServerManager.stop(projectID: project.id) }
            )
        }

        Button {
            appState.inspectionEnabled.toggle()
        } label: {
            Label(
                appState.inspectionEnabled ? "Disable Inspector" : "Enable Inspector",
                systemImage: appState.inspectionEnabled ? "eye.slash" : "eye"
            )
        }
        .help("Toggle element inspection (⌘I)")
        .keyboardShortcut("i", modifiers: .command)
        .disabled(appState.selectedProject == nil)
    }
}

// MARK: - Detail Content

private struct DetailContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VSplitView {
            PreviewContainer()
                .frame(minHeight: 300)

            ElementDetailPanel()
                .frame(minHeight: 200, idealHeight: 280)
        }
    }
}

// MARK: - Empty State

private struct EmptyProjectView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.rectangle.on.folder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Project Selected")
                .font(.title2)
                .fontWeight(.medium)

            Text("Add a project from the sidebar to start inspecting elements.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Dev Server Toolbar Button

struct DevServerToolbarButton: View {
    let isRunning: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        Button {
            if isRunning {
                onStop()
            } else {
                onStart()
            }
        } label: {
            Label(
                isRunning ? "Stop Dev Server" : "Start Dev Server",
                systemImage: isRunning ? "stop.fill" : "play.fill"
            )
        }
        .help(isRunning ? "Stop the dev server" : "Start the dev server")
    }
}

// MARK: - Claude Session Status Indicator

struct ClaudeSessionStatusIndicator: View {
    let status: ClaudeCodeSession.Status

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(status.displayText)
    }

    private var displayText: String {
        switch status {
        case .idle:
            return "Idle"
        case .starting:
            return "Starting..."
        case .ready:
            return "Ready"
        case .processing:
            return "Processing..."
        case .error:
            return "Error"
        }
    }

    private var statusColor: Color {
        switch status {
        case .idle: return .gray
        case .starting: return .yellow
        case .ready: return .green
        case .processing: return .blue
        case .error: return .red
        }
    }
}
