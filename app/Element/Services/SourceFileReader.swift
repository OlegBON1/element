import Foundation

enum SourceFileError: LocalizedError {
    case fileNotFound(String)
    case readError(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "File not found: \(path)"
        case .readError(let msg): return "Read error: \(msg)"
        }
    }
}

struct SourceFileReader {
    let projectPath: String
    let contextLines: Int

    init(projectPath: String, contextLines: Int = 10) {
        self.projectPath = projectPath
        self.contextLines = contextLines
    }

    func readSnippet(filePath: String, lineNumber: Int) throws -> String {
        let resolvedPath = resolvePath(filePath)

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw SourceFileError.fileNotFound(resolvedPath)
        }

        let content: String
        do {
            content = try String(contentsOfFile: resolvedPath, encoding: .utf8)
        } catch {
            throw SourceFileError.readError(error.localizedDescription)
        }

        let lines = content.components(separatedBy: .newlines)
        let targetIndex = lineNumber - 1 // 0-based
        let startIndex = max(0, targetIndex - contextLines)
        let endIndex = min(lines.count - 1, targetIndex + contextLines)

        guard startIndex <= endIndex, targetIndex >= 0, targetIndex < lines.count else {
            return content
        }

        let snippetLines = (startIndex...endIndex).map { index in
            let lineNum = index + 1
            let marker = lineNum == lineNumber ? " → " : "   "
            return "\(marker)\(lineNum) │ \(lines[index])"
        }

        return snippetLines.joined(separator: "\n")
    }

    private func resolvePath(_ filePath: String) -> String {
        if filePath.hasPrefix("/") {
            return filePath
        }

        let withProject = (projectPath as NSString).appendingPathComponent(filePath)
        if FileManager.default.fileExists(atPath: withProject) {
            return withProject
        }

        // Try removing leading ./ or src/ prefixes
        let cleaned = filePath
            .replacingOccurrences(of: "^\\./", with: "", options: .regularExpression)

        let withCleaned = (projectPath as NSString).appendingPathComponent(cleaned)
        if FileManager.default.fileExists(atPath: withCleaned) {
            return withCleaned
        }

        return withProject
    }
}
