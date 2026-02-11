import Foundation

struct ElementInfo: Codable, Identifiable, Equatable {
    let id: UUID
    let platform: PlatformType
    let componentName: String
    let filePath: String
    let lineNumber: Int
    let columnNumber: Int?
    let codeSnippet: String
    let componentTree: [String]
    let elementRect: ElementRect
    let tagName: String
    let textContent: String?
    let timestamp: Date
    let accessibilityIdentifier: String
    let childrenSummary: [String]

    struct ElementRect: Codable, Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    func withCodeSnippet(_ snippet: String) -> ElementInfo {
        ElementInfo(
            id: id,
            platform: platform,
            componentName: componentName,
            filePath: filePath,
            lineNumber: lineNumber,
            columnNumber: columnNumber,
            codeSnippet: snippet,
            componentTree: componentTree,
            elementRect: elementRect,
            tagName: tagName,
            textContent: textContent,
            timestamp: timestamp,
            accessibilityIdentifier: accessibilityIdentifier,
            childrenSummary: childrenSummary
        )
    }

    var hasSourceInfo: Bool {
        !filePath.isEmpty && lineNumber > 0
    }

    var displayPath: String {
        guard !filePath.isEmpty else { return "Unknown file" }
        let components = filePath.split(separator: "/")
        if components.count > 3 {
            return components.suffix(3).joined(separator: "/")
        }
        return filePath
    }

    var treeBreadcrumb: String {
        componentTree.joined(separator: " → ")
    }

    var frameDescription: String {
        "\(Int(elementRect.width))×\(Int(elementRect.height)) at (\(Int(elementRect.x)), \(Int(elementRect.y)))"
    }

    var childrenDescription: String {
        childrenSummary.isEmpty ? "none" : childrenSummary.joined(separator: ", ")
    }
}
