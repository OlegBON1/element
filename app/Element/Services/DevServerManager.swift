import Foundation

/// Manages dev server subprocesses for web projects.
/// Spawns processes like `npm run dev` in the project directory
/// and tracks their lifecycle per project.
@MainActor
final class DevServerManager: ObservableObject {
    @Published private(set) var runningServers: [UUID: ServerProcess] = [:]

    struct ServerProcess {
        let process: Process
        let projectID: UUID
        let command: String
        let startedAt: Date
    }

    // MARK: - Public API

    func start(project: ProjectConfig) {
        // Stop existing server for this project first
        stop(projectID: project.id)

        let command = Self.inferCommand(from: project.url)
        let escapedPath = project.path.replacingOccurrences(of: "'", with: "'\\''")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", "cd '\(escapedPath)' && \(command)"]
        proc.currentDirectoryURL = URL(fileURLWithPath: project.path)

        // Suppress output to avoid pipe buffer deadlocks
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.handleTermination(projectID: project.id)
            }
        }

        do {
            try proc.run()
            let serverProcess = ServerProcess(
                process: proc,
                projectID: project.id,
                command: command,
                startedAt: Date()
            )
            runningServers = runningServers.merging([project.id: serverProcess]) { _, new in new }
        } catch {
            NSLog("[DevServerManager] Failed to start server: %@", error.localizedDescription)
        }
    }

    func stop(projectID: UUID) {
        guard let serverProcess = runningServers[projectID] else { return }

        if serverProcess.process.isRunning {
            // Send SIGINT first (like Ctrl+C) for graceful shutdown
            kill(serverProcess.process.processIdentifier, SIGINT)

            // Force terminate after a short delay if still running
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if serverProcess.process.isRunning {
                    serverProcess.process.terminate()
                }
            }
        }

        runningServers = runningServers.filter { $0.key != projectID }
    }

    func stopAll() {
        let projectIDs = Array(runningServers.keys)
        for id in projectIDs {
            stop(projectID: id)
        }
    }

    func isRunning(projectID: UUID) -> Bool {
        guard let serverProcess = runningServers[projectID] else { return false }
        return serverProcess.process.isRunning
    }

    // MARK: - Command Detection

    static func inferCommand(from url: String) -> String {
        if url.contains(":3000") {
            return "npm run dev"
        } else if url.contains(":5173") || url.contains(":5174") {
            return "npm run dev"
        } else if url.contains(":8080") {
            return "npm run serve"
        } else if url.contains(":4200") {
            return "npm start"
        } else if url.contains(":8000") {
            return "npm run dev"
        } else {
            return "npm run dev"
        }
    }

    // MARK: - Private

    private func handleTermination(projectID: UUID) {
        runningServers = runningServers.filter { $0.key != projectID }
    }
}
