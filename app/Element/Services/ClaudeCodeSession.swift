import Foundation
import Combine

/// Write to a debug log file for troubleshooting subprocess issues.
/// Only active in DEBUG builds; logs are stored in ~/Library/Logs/Element/.
private func debugLog(_ message: String) {
    #if DEBUG
    let logDir = NSHomeDirectory() + "/Library/Logs/Element"
    let logFile = logDir + "/claude-session.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let entry = "[\(timestamp)] \(message)\n"
    if let data = entry.data(using: .utf8) {
        if !FileManager.default.fileExists(atPath: logDir) {
            try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        }
        if FileManager.default.fileExists(atPath: logFile) {
            if let handle = FileHandle(forWritingAtPath: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data)
        }
    }
    #endif
}

/// A live Claude Code session running as a subprocess.
/// Uses `claude -p --input-format stream-json --output-format stream-json --verbose`
/// to maintain a persistent session that accepts prompts via stdin.
@MainActor
final class ClaudeCodeSession: ObservableObject {

    enum Status: Equatable {
        case idle
        case starting
        case ready(sessionID: String)
        case processing
        case error(String)

        var isReady: Bool {
            if case .ready = self { return true }
            if case .processing = self { return true }
            return false
        }

        var displayText: String {
            switch self {
            case .idle: return "Not started"
            case .starting: return "Starting Claude Code…"
            case .ready: return "Ready"
            case .processing: return "Processing…"
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastResponse: String = ""
    @Published private(set) var streamingText: String = ""
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var sessionID: String?
    @Published private(set) var totalCost: Double = 0
    private(set) var currentProjectPath: String?

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var pendingCompletion: ((Result<String, Error>) -> Void)?

    // MARK: - Lifecycle

    /// Resolve the real path to the claude binary.
    private func resolveClaudePath() -> String? {
        // Try common locations
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]

        for candidate in candidates {
            let url = URL(fileURLWithPath: candidate)
            // Resolve symlinks
            if let resolved = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
               resolved.isSymbolicLink == true {
                if let realPath = try? URL(fileURLWithPath: candidate).resolvingSymlinksInPath(),
                   FileManager.default.isExecutableFile(atPath: realPath.path) {
                    return realPath.path
                }
            }
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // Fallback: use `which claude` via shell
        let whichProc = Process()
        whichProc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        whichProc.arguments = ["-l", "-c", "which claude"]
        let pipe = Pipe()
        whichProc.standardOutput = pipe
        whichProc.standardError = Pipe()
        do {
            try whichProc.run()
            whichProc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            debugLog("[ClaudeSession] which claude failed: \(error.localizedDescription)")
        }

        return nil
    }

    /// Build a suitable PATH environment for the subprocess.
    private func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Ensure common bin dirs are in PATH
        // Dynamically discover NVM node path if available
        var extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        // Add active NVM node version if present
        let nvmDir = "\(NSHomeDirectory())/.nvm/versions/node"
        if let nodeVersions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir),
           let latestVersion = nodeVersions.sorted().last {
            extraPaths.insert("\(nvmDir)/\(latestVersion)/bin", at: 1)
        }
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let combinedPath = (extraPaths + [currentPath]).joined(separator: ":")
        env["PATH"] = combinedPath
        return env
    }

    /// Start a Claude Code session for the given project directory.
    func start(projectPath: String) {
        guard status == .idle || {
            if case .error = status { return true }
            return false
        }() else { return }

        status = .starting
        currentProjectPath = projectPath

        guard let claudePath = resolveClaudePath() else {
            status = .error("Claude Code binary not found")
            debugLog("[ClaudeSession] ERROR: claude binary not found in any known location")
            return
        }

        debugLog("[ClaudeSession] Using claude at: \(claudePath)")
        debugLog("[ClaudeSession] Project path: \(projectPath)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)
        proc.arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--permission-mode", "acceptEdits"
        ]
        proc.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        proc.environment = buildEnvironment()

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr

        // Read stdout — JSON lines from Claude Code
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8)
            else { return }

            debugLog("[ClaudeSession] stdout: \(text.prefix(500))")

            Task { @MainActor [weak self] in
                self?.handleOutput(text)
            }
        }

        // Read stderr — log errors for debugging
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8)
            else { return }
            debugLog("[ClaudeSession] stderr: \(text.prefix(500))")
        }

        proc.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            debugLog("[ClaudeSession] Process terminated with code: \(code)")
            Task { @MainActor [weak self] in
                self?.handleTermination(exitCode: code)
            }
        }

        do {
            try proc.run()
            process = proc
            debugLog("[ClaudeSession] Process launched, PID: \(proc.processIdentifier)")

            // Claude Code in stream-json mode doesn't emit any output until the first
            // user message is sent. Mark the session as ready immediately once the
            // process is running — the session_id will be populated when the first
            // response arrives.
            status = .ready(sessionID: "pending")
        } catch {
            status = .error("Failed to start: \(error.localizedDescription)")
            debugLog("[ClaudeSession] ERROR launching: \(error.localizedDescription)")
        }
    }

    /// Send a prompt to the running Claude Code session.
    func send(prompt: String) async throws -> String {
        guard let stdinPipe = stdinPipe, process?.isRunning == true else {
            throw ClaudeSessionError.notRunning
        }

        isProcessing = true
        status = .processing
        lastResponse = ""
        streamingText = ""

        return try await withCheckedThrowingContinuation { continuation in
            pendingCompletion = { result in
                continuation.resume(with: result)
            }

            let message = StreamMessage(
                type: "user",
                message: StreamUserMessage(role: "user", content: prompt)
            )

            do {
                let jsonData = try JSONEncoder().encode(message)
                var payload = jsonData
                payload.append(contentsOf: "\n".utf8)

                debugLog("[ClaudeSession] Sending \(payload.count) bytes to stdin")
                stdinPipe.fileHandleForWriting.write(payload)
            } catch {
                isProcessing = false
                let sid = sessionID ?? "pending"
                status = .ready(sessionID: sid)
                pendingCompletion = nil
                continuation.resume(throwing: ClaudeSessionError.encodingFailed)
            }
        }
    }

    /// Stop the session.
    func stop() {
        debugLog("[ClaudeSession] Stopping session")
        stdinPipe?.fileHandleForWriting.closeFile()
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe = nil
        status = .idle
        isProcessing = false
        sessionID = nil
        currentProjectPath = nil
    }

    // MARK: - Output Parsing

    private func handleOutput(_ raw: String) {
        // stdout may contain multiple JSON lines
        let lines = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            parseLine(line)
        }
    }

    private func parseLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            debugLog("[ClaudeSession] Non-JSON line: \(line.prefix(200))")
            return
        }

        debugLog("[ClaudeSession] Parsed event type: \(type)")

        switch type {
        case "system":
            if let sid = json["session_id"] as? String {
                sessionID = sid
                debugLog("[ClaudeSession] Session ID received: \(sid)")
                // Update status with real session ID (was "pending" until now)
                if !isProcessing {
                    status = .ready(sessionID: sid)
                }
            }

        case "assistant":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if let blockType = block["type"] as? String,
                       blockType == "text",
                       let text = block["text"] as? String {
                        lastResponse += text
                        streamingText += text + "\n"
                    }
                    // Show tool use activity
                    if let blockType = block["type"] as? String,
                       blockType == "tool_use",
                       let toolName = block["name"] as? String {
                        streamingText += "[tool] Using \(toolName)...\n"
                    }
                }
            }

        case "result":
            if let resultText = json["result"] as? String {
                lastResponse = resultText
            }
            if let cost = json["total_cost_usd"] as? Double {
                totalCost += cost
            }

            isProcessing = false
            let sid = sessionID ?? "pending"
            status = .ready(sessionID: sid)

            let response = lastResponse
            pendingCompletion?(.success(response))
            pendingCompletion = nil

        default:
            break
        }
    }

    private func handleTermination(exitCode: Int32 = -1) {
        let wasProcessing = isProcessing
        isProcessing = false
        process = nil

        if wasProcessing {
            pendingCompletion?(.failure(ClaudeSessionError.sessionTerminated))
            pendingCompletion = nil
        }

        // If it terminated while we were still in .starting, it's an error
        if case .starting = status {
            status = .error("Claude Code exited (code \(exitCode)) — check logs")
        } else {
            status = .idle
        }
    }
}

// MARK: - Types

enum ClaudeSessionError: LocalizedError {
    case notRunning
    case encodingFailed
    case sessionTerminated

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Claude Code session is not running. Start it first."
        case .encodingFailed: return "Failed to encode prompt message."
        case .sessionTerminated: return "Claude Code session terminated unexpectedly."
        }
    }
}

private struct StreamMessage: Encodable {
    let type: String
    let message: StreamUserMessage
}

private struct StreamUserMessage: Encodable {
    let role: String
    let content: String
}
