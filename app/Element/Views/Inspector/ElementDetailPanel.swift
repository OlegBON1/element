import SwiftUI
import AppKit

struct ElementDetailPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if let element = appState.selectedElement {
                SelectedElementView(element: element)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("No Element Selected")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Enable the inspector and click on an element in the preview.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
    }
}

// MARK: - Selected Element View

private struct SelectedElementView: View {
    let element: ElementInfo
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var claudeSession: ClaudeCodeSession
    @State private var sendResult: SendResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                sourceSection
                codeSection
                promptSection
                claudeSessionSection
                actionSection
                responseSection
            }
            .padding()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: element.platform.iconName)
                        .foregroundStyle(.blue)

                    Text(element.componentName)
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                if !element.treeBreadcrumb.isEmpty {
                    Text(element.treeBreadcrumb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contextMenu { copyContextMenu }

            Spacer()

            copyMenuButton

            Button {
                appState.clearSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Copy Menu

    @ViewBuilder
    private var copyContextMenu: some View {
        Button("Copy as Prompt") {
            ClipboardService.copy(element, format: .prompt)
        }
        Button("Copy File Path") {
            ClipboardService.copy(element, format: .filePath)
        }
        if !element.codeSnippet.isEmpty {
            Button("Copy Code Snippet") {
                ClipboardService.copy(element, format: .codeSnippet)
            }
        }
        Button("Copy as JSON") {
            ClipboardService.copy(element, format: .json)
        }
    }

    private var copyMenuButton: some View {
        Menu {
            copyContextMenu
        } label: {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
        .help("Copy element info")
    }

    // MARK: - Source Info

    private var sourceSection: some View {
        Group {
            if element.hasSourceInfo {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Source Location")

                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(element.displayPath)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)

                            Text("Line \(element.lineNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Element Details")

                    VStack(alignment: .leading, spacing: 4) {
                        detailRow(label: "Type", value: element.tagName)
                        if let text = element.textContent, !text.isEmpty {
                            detailRow(label: "Text", value: text)
                        }
                        if !element.accessibilityIdentifier.isEmpty {
                            detailRow(label: "ID", value: element.accessibilityIdentifier)
                        }
                        detailRow(label: "Frame", value: element.frameDescription)
                        if !element.childrenSummary.isEmpty {
                            detailRow(
                                label: "Children",
                                value: element.childrenDescription
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Code Snippet

    private var codeSection: some View {
        Group {
            if !element.codeSnippet.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Code")

                    CodeSnippetView(snippet: element.codeSnippet)
                }
            }
        }
    }

    // MARK: - Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Instruction")

            TextField(
                "What should Claude Code do with this element?",
                text: $appState.promptInstruction,
                axis: .vertical
            )
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Claude Session Status

    private var claudeSessionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Claude Code Session")

            HStack(spacing: 8) {
                Circle()
                    .fill(sessionStatusColor)
                    .frame(width: 8, height: 8)

                Text(claudeSession.status.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if claudeSession.status == .idle || {
                    if case .error = claudeSession.status { return true }
                    return false
                }() {
                    Button("Start") {
                        if let project = appState.selectedProject {
                            claudeSession.start(projectPath: project.path)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if claudeSession.status.isReady {
                    Button("Stop") {
                        claudeSession.stop()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }

            if claudeSession.totalCost > 0 {
                Text(String(format: "Session cost: $%.4f", claudeSession.totalCost))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var sessionStatusColor: Color {
        switch claudeSession.status {
        case .idle: return .gray
        case .starting: return .yellow
        case .ready: return .green
        case .processing: return .blue
        case .error: return .red
        }
    }

    // MARK: - Action

    private var actionSection: some View {
        VStack(spacing: 8) {
            Button {
                sendToClaudeCode()
            } label: {
                HStack {
                    if claudeSession.isProcessing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(claudeSession.isProcessing ? "Processing…" : "Send to Claude Code")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend)

            Button {
                copyPromptToClipboard()
            } label: {
                HStack {
                    Image(systemName: "doc.on.clipboard")
                    Text("Copy Prompt")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(!appState.canSendToClaudeCode)

            if let result = sendResult {
                resultBanner(result)
            }
        }
    }

    private var canSend: Bool {
        appState.canSendToClaudeCode
            && claudeSession.status.isReady
            && !claudeSession.isProcessing
    }

    // MARK: - Response

    private var responseSection: some View {
        Group {
            // Show streaming activity while processing
            if claudeSession.isProcessing, !claudeSession.streamingText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Activity")

                    Text(claudeSession.streamingText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color(.textBackgroundColor).opacity(0.3),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                }
            }

            // Show final response
            if !claudeSession.isProcessing, !claudeSession.lastResponse.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SectionHeader(title: "Claude Code Response")
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                claudeSession.lastResponse, forType: .string
                            )
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Copy response")
                    }

                    Text(claudeSession.lastResponse)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color(.textBackgroundColor).opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func resultBanner(_ result: SendResult) -> some View {
        HStack(spacing: 6) {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text(result.message)
                .font(.caption)
        }
        .foregroundStyle(result.isSuccess ? .green : .red)
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            (result.isSuccess ? Color.green : Color.red).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Actions

    private func sendToClaudeCode() {
        guard let prompt = appState.renderedPrompt else { return }

        Task {
            do {
                let response = try await claudeSession.send(prompt: prompt)
                NSLog("[Element] Claude Code response: %d chars", response.count)
                showResult(success: true, message: "Sent to Claude Code")
            } catch {
                NSLog("[Element] Send error: %@", error.localizedDescription)
                showResult(success: false, message: error.localizedDescription)
            }
        }
    }

    private func copyPromptToClipboard() {
        guard let prompt = appState.renderedPrompt else {
            ClipboardService.copy(element, format: .prompt)
            showResult(success: true, message: "Copied to clipboard")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        showResult(success: true, message: "Copied to clipboard")
    }

    private func showResult(success: Bool, message: String) {
        sendResult = SendResult(isSuccess: success, message: message)
        Task {
            try? await Task.sleep(for: .seconds(3))
            sendResult = nil
        }
    }
}

// MARK: - Supporting Types

private struct SendResult {
    let isSuccess: Bool
    let message: String
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}
