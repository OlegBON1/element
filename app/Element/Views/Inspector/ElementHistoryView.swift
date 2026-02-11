import SwiftUI

struct ElementHistoryView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if appState.elementHistory.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Recent Elements", systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Spacer()

            if !appState.elementHistory.isEmpty {
                Button {
                    appState.elementHistory.clear()
                } label: {
                    Text("Clear")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - List

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(
                    Array(appState.elementHistory.items.enumerated()),
                    id: \.element.id
                ) { index, element in
                    HistoryRow(element: element) {
                        appState.selectElement(element)
                    } onRemove: {
                        appState.elementHistory.remove(at: index)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No recent elements")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let element: ElementInfo
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: element.platform.iconName)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(element.componentName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if element.hasSourceInfo {
                        Text(element.displayPath + ":\(element.lineNumber)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(relativeTime(element.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Select") { onSelect() }
            Button("Copy File Path") {
                ClipboardService.copy(element, format: .filePath)
            }
            Divider()
            Button("Remove", role: .destructive) { onRemove() }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}
