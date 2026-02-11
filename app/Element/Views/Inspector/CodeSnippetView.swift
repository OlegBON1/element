import SwiftUI

struct CodeSnippetView: View {
    let snippet: String
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            copyButton

            ScrollView(.horizontal, showsIndicators: true) {
                Text(snippet)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(.textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    private var copyButton: some View {
        HStack {
            Spacer()

            Button {
                copyToClipboard()
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Copy code snippet")
            .padding(4)
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
        isCopied = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            isCopied = false
        }
    }
}
