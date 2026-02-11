import Foundation

/// Maps iOS accessibility hierarchy nodes to Swift source code locations
/// using heuristic matching. Since Swift has no equivalent of React's
/// `_debugSource`, we rely on:
/// 1. accessibilityIdentifier → search for matching identifier in code
/// 2. View type name → search for struct/class declaration
/// 3. Text content → search for string literals
/// 4. Custom markers → @ElementID attributes
struct SwiftSourceMapper {
    let projectPath: String

    struct SourceMatch: Equatable {
        let filePath: String
        let lineNumber: Int
        let confidence: MatchConfidence
        let matchType: MatchType
    }

    enum MatchConfidence: Int, Comparable {
        case low = 1
        case medium = 2
        case high = 3

        static func < (lhs: MatchConfidence, rhs: MatchConfidence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    enum MatchType: String {
        case accessibilityIdentifier
        case viewType
        case textContent
        case customMarker
    }

    // MARK: - Public API

    func findSource(for node: AccessibilityNode) -> SourceMatch? {
        let candidates = collectCandidates(for: node)
        return candidates
            .sorted { $0.confidence > $1.confidence }
            .first
    }

    func findSource(
        identifier: String,
        viewType: String,
        textContent: String
    ) -> SourceMatch? {
        let node = AccessibilityNode(
            label: textContent,
            identifier: identifier,
            type: viewType,
            frame: .zero,
            children: []
        )
        return findSource(for: node)
    }

    // MARK: - Candidate Collection

    private func collectCandidates(for node: AccessibilityNode) -> [SourceMatch] {
        var candidates: [SourceMatch] = []

        if !node.identifier.isEmpty {
            candidates.append(contentsOf: searchByIdentifier(node.identifier))
        }

        if !node.type.isEmpty {
            candidates.append(contentsOf: searchByViewType(node.type))
        }

        if !node.label.isEmpty {
            candidates.append(contentsOf: searchByTextContent(node.label))
        }

        return candidates
    }

    // MARK: - Search Strategies

    private func searchByIdentifier(_ identifier: String) -> [SourceMatch] {
        let patterns = [
            "\\.accessibilityIdentifier\\(\"\(escaped(identifier))\"\\)",
            "#Preview.*\(escaped(identifier))",
            "@ElementID.*\(escaped(identifier))",
        ]

        return searchSwiftFiles(patterns: patterns, matchType: .accessibilityIdentifier, confidence: .high)
    }

    private func searchByViewType(_ typeName: String) -> [SourceMatch] {
        let cleanType = typeName
            .replacingOccurrences(of: "UIKit.", with: "")
            .replacingOccurrences(of: "SwiftUI.", with: "")

        let patterns = [
            "struct\\s+\(escaped(cleanType))\\s*:\\s*View",
            "class\\s+\(escaped(cleanType))\\s*:",
            "struct\\s+\(escaped(cleanType))\\s*\\{",
        ]

        return searchSwiftFiles(patterns: patterns, matchType: .viewType, confidence: .medium)
    }

    private func searchByTextContent(_ text: String) -> [SourceMatch] {
        guard text.count >= 3, text.count <= 100 else { return [] }

        let patterns = [
            "Text\\(\"\(escaped(text))\"\\)",
            "Label\\(\"\(escaped(text))\"",
            "Button\\(\"\(escaped(text))\"",
            "\\.navigationTitle\\(\"\(escaped(text))\"\\)",
        ]

        return searchSwiftFiles(patterns: patterns, matchType: .textContent, confidence: .low)
    }

    // MARK: - File Search

    private func searchSwiftFiles(
        patterns: [String],
        matchType: MatchType,
        confidence: MatchConfidence
    ) -> [SourceMatch] {
        let swiftFiles = findSwiftFiles()
        var matches: [SourceMatch] = []

        for filePath in swiftFiles {
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                continue
            }

            let lines = content.components(separatedBy: .newlines)

            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                    continue
                }

                for (index, line) in lines.enumerated() {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    if regex.firstMatch(in: line, range: range) != nil {
                        let relativePath = filePath.replacingOccurrences(of: projectPath + "/", with: "")
                        matches.append(SourceMatch(
                            filePath: relativePath,
                            lineNumber: index + 1,
                            confidence: confidence,
                            matchType: matchType
                        ))
                    }
                }
            }
        }

        return matches
    }

    private func findSwiftFiles() -> [String] {
        let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: projectPath),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var files: [String] = []

        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" {
                let path = url.path
                // Skip build artifacts, derived data, pods
                if !path.contains("/DerivedData/")
                    && !path.contains("/build/")
                    && !path.contains("/Pods/")
                    && !path.contains("/.build/")
                    && !path.contains("/Packages/") {
                    files.append(path)
                }
            }
        }

        return files
    }

    // MARK: - Helpers

    private func escaped(_ string: String) -> String {
        NSRegularExpression.escapedPattern(for: string)
    }
}
