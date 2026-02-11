import AppKit
import Foundation

/// Periodically captures screenshots from the iOS Simulator
/// and provides them as NSImage frames for display.
@MainActor
final class ScreenMirrorService: ObservableObject {
    @Published private(set) var currentFrame: NSImage?
    @Published private(set) var isCapturing = false
    @Published private(set) var lastError: String?

    private let simulator = SimulatorService()
    private var captureTask: Task<Void, Never>?
    private var deviceUDID: String?

    /// Frames per second for screen capture.
    private let fps: Double = 2

    // MARK: - Lifecycle

    func startCapture(deviceUDID: String) {
        stopCapture()

        self.deviceUDID = deviceUDID
        isCapturing = true
        lastError = nil

        captureTask = Task { [weak self] in
            guard let self else { return }
            await self.captureLoop()
        }
    }

    func stopCapture() {
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
    }

    // MARK: - Capture Loop

    private func captureLoop() async {
        let interval = 1.0 / fps

        while !Task.isCancelled {
            await captureOnce()
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    private func captureOnce() async {
        guard let udid = deviceUDID else { return }

        do {
            let data = try await simulator.captureScreenshot(deviceUDID: udid)

            guard let image = NSImage(data: data) else {
                lastError = "Failed to decode screenshot"
                return
            }

            currentFrame = image
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    deinit {
        captureTask?.cancel()
    }
}
