import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState

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
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarContent
            }
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        BridgeStatusIndicator(status: appState.bridgeStatus)

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

// MARK: - Bridge Status Indicator

struct BridgeStatusIndicator: View {
    let status: BridgeStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(status.connection.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(statusTooltip)
    }

    private var statusColor: Color {
        switch status.connection {
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .connected: return status.childAlive ? .green : .orange
        case .error: return .red
        }
    }

    private var statusTooltip: String {
        var parts = [status.connection.displayText]
        if status.connection.isConnected {
            parts.append("Queue: \(status.queueLength)")
            parts.append(status.childAlive ? "Claude Code: Running" : "Claude Code: Stopped")
            parts.append(status.idle ? "Idle" : "Busy")
        }
        return parts.joined(separator: " | ")
    }
}
