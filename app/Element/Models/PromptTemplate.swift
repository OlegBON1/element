import Foundation

struct PromptTemplate: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let template: String
    let isDefault: Bool

    func render(element: ElementInfo, instruction: String) -> String {
        template
            .replacingOccurrences(of: "{{componentName}}", with: element.componentName)
            .replacingOccurrences(of: "{{filePath}}", with: element.filePath)
            .replacingOccurrences(of: "{{lineNumber}}", with: String(element.lineNumber))
            .replacingOccurrences(of: "{{columnNumber}}", with: String(element.columnNumber ?? 0))
            .replacingOccurrences(of: "{{codeSnippet}}", with: element.codeSnippet)
            .replacingOccurrences(of: "{{componentTree}}", with: element.treeBreadcrumb)
            .replacingOccurrences(of: "{{tagName}}", with: element.tagName)
            .replacingOccurrences(of: "{{textContent}}", with: element.textContent ?? "")
            .replacingOccurrences(of: "{{frame}}", with: element.frameDescription)
            .replacingOccurrences(of: "{{identifier}}", with: element.accessibilityIdentifier)
            .replacingOccurrences(of: "{{children}}", with: element.childrenDescription)
            .replacingOccurrences(of: "{{instruction}}", with: instruction)
    }

    func withTemplate(_ newTemplate: String) -> PromptTemplate {
        PromptTemplate(
            id: id,
            name: name,
            template: newTemplate,
            isDefault: isDefault
        )
    }

    static let defaultTemplate = PromptTemplate(
        id: UUID(),
        name: "Default",
        template: """
        Edit the {{componentName}} component in {{filePath}} at line {{lineNumber}}.

        Component tree: {{componentTree}}

        Current code:
        ```
        {{codeSnippet}}
        ```

        {{instruction}}
        """,
        isDefault: true
    )

    static let minimalTemplate = PromptTemplate(
        id: UUID(),
        name: "Minimal",
        template: "Edit {{filePath}}:{{lineNumber}} ({{componentName}}). {{instruction}}",
        isDefault: false
    )

    static let inspectorTemplate = PromptTemplate(
        id: UUID(),
        name: "Inspector",
        template: """
        I selected a UI element in the running iOS app via accessibility inspector:

        - Type: {{tagName}}
        - Component: {{componentName}}
        - Text: {{textContent}}
        - Accessibility ID: {{identifier}}
        - Frame: {{frame}}
        - Hierarchy: {{componentTree}}
        - Children: {{children}}

        {{instruction}}
        """,
        isDefault: false
    )

    static let allDefaults: [PromptTemplate] = [defaultTemplate, minimalTemplate, inspectorTemplate]

    /// Returns the best template for a given element (prefers source-based if source info is available).
    static func bestTemplate(for element: ElementInfo) -> PromptTemplate {
        if element.hasSourceInfo {
            return defaultTemplate
        }
        return inspectorTemplate
    }
}
