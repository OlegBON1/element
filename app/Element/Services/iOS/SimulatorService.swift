import AppKit
import Foundation

enum SimulatorError: LocalizedError {
    case noBootedDevice
    case commandFailed(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .noBootedDevice: return "No booted iOS Simulator found"
        case .commandFailed(let msg): return "Simulator command failed: \(msg)"
        case .parseError(let msg): return "Failed to parse simulator data: \(msg)"
        }
    }
}

struct SimulatorDevice: Codable, Identifiable, Equatable {
    let udid: String
    let name: String
    let state: String
    let runtime: String

    var id: String { udid }
    var isBooted: Bool { state == "Booted" }
}

struct AccessibilityNode: Equatable {
    let label: String
    let identifier: String
    let type: String
    let frame: CGRect
    let children: [AccessibilityNode]
}

actor SimulatorService {

    // MARK: - Device Discovery

    func bootedDevices() async throws -> [SimulatorDevice] {
        let output = try await runXcrun(["simctl", "list", "devices", "--json"])

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesMap = json["devices"] as? [String: [[String: Any]]]
        else {
            throw SimulatorError.parseError("Cannot parse device list")
        }

        var devices: [SimulatorDevice] = []
        for (runtime, deviceList) in devicesMap {
            for device in deviceList {
                guard let state = device["state"] as? String, state == "Booted",
                      let udid = device["udid"] as? String,
                      let name = device["name"] as? String
                else { continue }

                devices.append(SimulatorDevice(
                    udid: udid,
                    name: name,
                    state: state,
                    runtime: runtime
                ))
            }
        }

        guard !devices.isEmpty else {
            throw SimulatorError.noBootedDevice
        }

        return devices
    }

    // MARK: - Accessibility Hierarchy

    func accessibilityHierarchy(deviceUDID: String, bundleID: String) async throws -> [AccessibilityNode] {
        // Use `idb` (Facebook's iOS Development Bridge) if available,
        // otherwise fall back to `xcrun simctl` accessibility inspection
        if await isIDBAvailable() {
            return try await fetchHierarchyViaIDB(deviceUDID: deviceUDID, bundleID: bundleID)
        }
        return try await fetchHierarchyViaSimctl(deviceUDID: deviceUDID)
    }

    // MARK: - Screenshot

    func captureScreenshot(deviceUDID: String) async throws -> Data {
        let tmpPath = NSTemporaryDirectory() + "element_sim_\(UUID().uuidString).png"
        _ = try await runXcrun(["simctl", "io", deviceUDID, "screenshot", tmpPath])

        let url = URL(fileURLWithPath: tmpPath)
        let data = try Data(contentsOf: url)
        try? FileManager.default.removeItem(atPath: tmpPath)
        return data
    }

    // MARK: - Tap Simulation

    func simulateTap(deviceUDID: String, x: Int, y: Int) async throws {
        _ = try await runXcrun(["simctl", "io", deviceUDID, "tap", "\(x)", "\(y)"])
    }

    // MARK: - Window Bounds

    /// Returns the simulator window's content area bounds in screen coordinates.
    /// Used to convert between screenshot image coordinates and AX screen coordinates.
    nonisolated func simulatorWindowContentBounds() -> CGRect? {
        guard let simulatorApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.iphonesimulator"
        ).first else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(simulatorApp.processIdentifier)

        // Get the first window
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement],
              let window = windows.first
        else {
            return nil
        }

        // Find the content area - look for AXScrollArea or AXGroup inside window
        // which represents the simulator screen content (not title bar)
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else {
            return axFrame(window)
        }

        // The simulator content is usually the largest child element
        var bestFrame = CGRect.zero
        for child in children {
            let frame = axFrame(child)
            if frame.width * frame.height > bestFrame.width * bestFrame.height {
                bestFrame = frame
            }
        }

        return bestFrame.isEmpty ? axFrame(window) : bestFrame
    }

    // MARK: - IDB Integration

    private func isIDBAvailable() async -> Bool {
        let result = try? await runShell("/usr/bin/which", arguments: ["idb"])
        return result?.isEmpty == false
    }

    private func fetchHierarchyViaIDB(deviceUDID: String, bundleID: String) async throws -> [AccessibilityNode] {
        let output = try await runShell(
            "/usr/local/bin/idb",
            arguments: ["ui", "describe-all", "--udid", deviceUDID, "--json"]
        )

        guard let data = output.data(using: .utf8),
              let elements = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            throw SimulatorError.parseError("Cannot parse idb accessibility data")
        }

        return elements.map { parseIDBNode($0) }
    }

    private func fetchHierarchyViaSimctl(deviceUDID: String) async throws -> [AccessibilityNode] {
        // Use macOS Accessibility API (AXUIElement) to read the Simulator
        // window's accessibility tree. This requires the user to grant
        // Accessibility permission to the Element app in System Settings.
        return fetchSimulatorAXTree()
    }

    private nonisolated func fetchSimulatorAXTree() -> [AccessibilityNode] {
        // Check if we have AX permission at all
        let trusted = AXIsProcessTrusted()
        NSLog("[ElementAX] AXIsProcessTrusted = %@", trusted ? "YES" : "NO")

        guard let simulatorApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.iphonesimulator"
        ).first else {
            NSLog("[ElementAX] Simulator app NOT found")
            return []
        }

        NSLog("[ElementAX] Simulator PID: %d", simulatorApp.processIdentifier)
        let appElement = AXUIElementCreateApplication(simulatorApp.processIdentifier)

        // Get the main window
        var windowValue: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)
        NSLog("[ElementAX] Focused window result: %d", focusResult.rawValue)

        if focusResult == .success, let window = windowValue {
            // CFTypeRef from AXUIElement API is always an AXUIElement for window attributes
            let windowElement = window as! AXUIElement
            let children = readAXChildren(of: windowElement, depth: 0, maxDepth: 15)
            NSLog("[ElementAX] Read %d children from focused window", children.count)
            return children
        }

        // Try getting first window instead
        var windowsValue: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        NSLog("[ElementAX] Windows list result: %d", windowsResult.rawValue)

        guard let windows = windowsValue as? [AXUIElement],
              let firstWindow = windows.first
        else {
            NSLog("[ElementAX] No windows found")
            return []
        }

        NSLog("[ElementAX] Using first of %d windows", windows.count)
        let children = readAXChildren(of: firstWindow, depth: 0, maxDepth: 15)
        NSLog("[ElementAX] Read %d children from first window", children.count)
        return children
    }

    private nonisolated func readAXChildren(of element: AXUIElement, depth: Int, maxDepth: Int) -> [AccessibilityNode] {
        guard depth < maxDepth else { return [] }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else {
            return []
        }

        return children.map { child in
            let label = axString(child, kAXDescriptionAttribute as CFString)
                ?? axString(child, kAXTitleAttribute as CFString)
                ?? axString(child, kAXValueAttribute as CFString)
                ?? ""
            let identifier = axString(child, kAXIdentifierAttribute as CFString) ?? ""
            let role = axString(child, kAXRoleAttribute as CFString) ?? "Unknown"
            let frame = axFrame(child)

            let childNodes = readAXChildren(of: child, depth: depth + 1, maxDepth: maxDepth)

            return AccessibilityNode(
                label: label,
                identifier: identifier,
                type: role,
                frame: frame,
                children: childNodes
            )
        }
    }

    private nonisolated func axString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let str = value as? String, !str.isEmpty
        else { return nil }
        return str
    }

    private nonisolated func axFrame(_ element: AXUIElement) -> CGRect {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else {
            return .zero
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        // CFTypeRef values from AXUIElement are always AXValue for position/size
        let posAXValue = posValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        AXValueGetValue(posAXValue, .cgPoint, &position)
        AXValueGetValue(sizeAXValue, .cgSize, &size)

        return CGRect(origin: position, size: size)
    }

    private func parseIDBNode(_ json: [String: Any]) -> AccessibilityNode {
        let frame = json["frame"] as? [String: Double] ?? [:]
        let childrenJSON = json["children"] as? [[String: Any]] ?? []

        return AccessibilityNode(
            label: json["AXLabel"] as? String ?? "",
            identifier: json["AXIdentifier"] as? String ?? "",
            type: json["type"] as? String ?? "Unknown",
            frame: CGRect(
                x: frame["x"] ?? 0,
                y: frame["y"] ?? 0,
                width: frame["width"] ?? 0,
                height: frame["height"] ?? 0
            ),
            children: childrenJSON.map { parseIDBNode($0) }
        )
    }

    // MARK: - Shell Execution

    private func runXcrun(_ arguments: [String]) async throws -> String {
        try await runShell("/usr/bin/xcrun", arguments: arguments)
    }

    private func runShell(_ path: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        // Prevent terminal window from opening
        process.standardInput = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            throw SimulatorError.commandFailed(errorOutput.isEmpty ? "Exit code \(process.terminationStatus)" : errorOutput)
        }

        return output
    }
}
