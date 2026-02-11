import AppKit

enum ClipboardFormat {
    case prompt
    case filePath
    case codeSnippet
    case json
}

struct ClipboardService {
    static func copy(_ element: ElementInfo, format: ClipboardFormat) {
        let text: String

        switch format {
        case .prompt:
            text = PromptTemplate.defaultTemplate.render(
                element: element,
                instruction: ""
            )
        case .filePath:
            text = "\(element.filePath):\(element.lineNumber)"
        case .codeSnippet:
            text = element.codeSnippet
        case .json:
            text = elementToJSON(element)
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func elementToJSON(_ element: ElementInfo) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(element),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return json
    }
}
