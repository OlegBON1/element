import Foundation

@MainActor
final class BridgeProcessManager: ObservableObject {
    @Published private(set) var isRunning = false

    private var process: Process?
    private var healthCheckTask: Task<Void, Never>?
    private let client: BridgeClient
    private let onStatusUpdate: (BridgeStatus) -> Void

    init(client: BridgeClient, onStatusUpdate: @escaping (BridgeStatus) -> Void) {
        self.client = client
        self.onStatusUpdate = onStatusUpdate
    }

    func start(bridgePath: String? = nil, command: String = "claude") {
        let resolvedPath = bridgePath ?? findBridgeBinary()
        guard let path = resolvedPath else {
            onStatusUpdate(BridgeStatus(
                connection: .error("element-bridge binary not found"),
                idle: false,
                queueLength: 0,
                childAlive: false
            ))
            return
        }

        stop()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--verbose", command]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.handleTermination()
            }
        }

        do {
            try proc.run()
            process = proc
            isRunning = true
            onStatusUpdate(BridgeStatus.disconnected.withConnection(.connecting))
            startHealthCheck()
        } catch {
            onStatusUpdate(BridgeStatus(
                connection: .error("Failed to start bridge: \(error.localizedDescription)"),
                idle: false,
                queueLength: 0,
                childAlive: false
            ))
        }
    }

    func stop() {
        healthCheckTask?.cancel()
        healthCheckTask = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        isRunning = false
        onStatusUpdate(.disconnected)
    }

    private func startHealthCheck() {
        healthCheckTask = Task { [weak self] in
            // Give bridge time to start
            try? await Task.sleep(for: .seconds(1))

            while !Task.isCancelled {
                await self?.pollStatus()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func pollStatus() async {
        do {
            let status = try await client.getStatus()
            onStatusUpdate(BridgeStatus(
                connection: .connected,
                idle: status.idle,
                queueLength: status.queue_length,
                childAlive: status.child_alive
            ))
        } catch {
            if isRunning {
                onStatusUpdate(BridgeStatus.disconnected.withConnection(.connecting))
            }
        }
    }

    private func handleTermination() {
        isRunning = false
        healthCheckTask?.cancel()
        onStatusUpdate(BridgeStatus(
            connection: .error("Bridge process terminated"),
            idle: false,
            queueLength: 0,
            childAlive: false
        ))
    }

    private func findBridgeBinary() -> String? {
        let candidates = [
            Bundle.main.path(forResource: "element-bridge", ofType: nil),
            "\(NSHomeDirectory())/.local/bin/element-bridge",
            "/usr/local/bin/element-bridge",
            "/opt/homebrew/bin/element-bridge",
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
