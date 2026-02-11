import AppKit
import Foundation

/// Coordinates iOS Simulator element inspection by combining
/// SimulatorService (device/accessibility) with SwiftSourceMapper (source lookup).
@MainActor
final class IOSInspectorService: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isInspecting = false
    @Published private(set) var bootedDevices: [SimulatorDevice] = []
    @Published var selectedDeviceUDID: String?

    /// The selected node's frame in screen (AX) coordinates, for highlight overlay.
    @Published private(set) var selectedNodeFrame: CGRect?

    /// Cached window bounds for coordinate mapping.
    @Published private(set) var cachedWindowBounds: CGRect?

    /// Whether accessibility permission is granted.
    @Published private(set) var hasAccessibilityPermission = false

    private let simulator = SimulatorService()
    private var sourceMapper: SwiftSourceMapper?
    private var onElementSelected: ((ElementInfo) -> Void)?
    private var projectPath: String = ""

    /// Cached AX hierarchy to avoid re-fetching on every click.
    private var cachedNodes: [AccessibilityNode] = []
    private var cacheTimestamp: Date = .distantPast
    private let cacheTTL: TimeInterval = 2.0

    // MARK: - Configuration

    func configure(
        projectPath: String,
        onElementSelected: @escaping (ElementInfo) -> Void
    ) {
        self.projectPath = projectPath
        self.sourceMapper = SwiftSourceMapper(projectPath: projectPath)
        self.onElementSelected = onElementSelected
    }

    // MARK: - Device Discovery

    func refreshDevices() async {
        do {
            let devices = try await simulator.bootedDevices()
            bootedDevices = devices
            isConnected = !devices.isEmpty

            if selectedDeviceUDID == nil {
                selectedDeviceUDID = devices.first?.udid
            }
        } catch {
            bootedDevices = []
            isConnected = false
        }
    }

    // MARK: - Inspection

    func enableInspection() {
        isInspecting = true
        hasAccessibilityPermission = AXIsProcessTrusted()
        debugLog("Inspection enabled. AXIsProcessTrusted = \(hasAccessibilityPermission)")
        // Pre-fetch AX hierarchy when inspection is enabled
        Task { await refreshAXCache() }
    }

    func disableInspection() {
        isInspecting = false
        selectedNodeFrame = nil
        cachedNodes = []
    }

    /// Debug log visible in Console.app (filter by "Element" subsystem).
    private func debugLog(_ message: String) {
        NSLog("[ElementInspector] %@", message)
    }

    /// Inspect element at a point in screenshot image coordinates.
    func inspectElementAtPoint(x: Double, y: Double, imageSize: CGSize) async {
        guard let udid = selectedDeviceUDID,
              isInspecting
        else {
            debugLog("inspectElementAtPoint: guard failed - udid=\(selectedDeviceUDID ?? "nil"), isInspecting=\(isInspecting)")
            return
        }

        debugLog("Click at image coords: (\(Int(x)), \(Int(y))), imageSize: \(Int(imageSize.width))x\(Int(imageSize.height))")

        // Use cached nodes if fresh, otherwise fetch
        let nodes: [AccessibilityNode]
        if Date().timeIntervalSince(cacheTimestamp) < cacheTTL, !cachedNodes.isEmpty {
            nodes = cachedNodes
            debugLog("Using cached AX nodes: \(cachedNodes.count) top-level")
        } else {
            do {
                nodes = try await simulator.accessibilityHierarchy(
                    deviceUDID: udid,
                    bundleID: ""
                )
                cachedNodes = nodes
                cacheTimestamp = Date()
                debugLog("Fetched AX nodes: \(nodes.count) top-level, \(flattenNodes(nodes).count) total")
            } catch {
                debugLog("AX hierarchy fetch FAILED: \(error)")
                return
            }
        }

        // Get simulator window content bounds (cached)
        let windowBounds = cachedWindowBounds ?? simulator.simulatorWindowContentBounds()
        if cachedWindowBounds == nil {
            cachedWindowBounds = windowBounds
        }
        debugLog("Window bounds: \(windowBounds.map { "\(Int($0.origin.x)),\(Int($0.origin.y)) \(Int($0.width))x\(Int($0.height))" } ?? "nil")")

        let screenPoint: CGPoint
        if let bounds = windowBounds, bounds.width > 0, bounds.height > 0 {
            let scaleX = bounds.width / imageSize.width
            let scaleY = bounds.height / imageSize.height
            screenPoint = CGPoint(
                x: bounds.origin.x + x * scaleX,
                y: bounds.origin.y + y * scaleY
            )
        } else {
            screenPoint = CGPoint(x: x, y: y)
        }
        debugLog("Screen point: (\(Int(screenPoint.x)), \(Int(screenPoint.y)))")

        let allFlat = flattenNodes(nodes)

        // Log a few sample node frames for debugging
        for (i, node) in allFlat.prefix(5).enumerated() {
            debugLog("  Node[\(i)]: type=\(node.type), label=\(node.label.prefix(20)), frame=\(Int(node.frame.origin.x)),\(Int(node.frame.origin.y)) \(Int(node.frame.width))x\(Int(node.frame.height))")
        }

        // Determine screen area for filtering oversized elements
        let screenArea: Double
        if let bounds = windowBounds {
            screenArea = bounds.width * bounds.height
        } else {
            screenArea = imageSize.width * imageSize.height
        }

        // Primary: exact hit test (deepest child in tree)
        if let hitNode = findNodeAtPoint(nodes: nodes, point: screenPoint) {
            let hitArea = hitNode.frame.width * hitNode.frame.height
            let hitRatio = hitArea / screenArea
            // Only skip if element covers nearly the entire screen (>85%)
            // Cards, banners, etc. (20-70% of screen) should still be selectable
            if hitRatio > 0.85 {
                debugLog("HIT (exact) nearly full-screen (\(Int(hitRatio*100))%%): type=\(hitNode.type), trying smaller...")
                if let better = findSmallestContainingNode(nodes: allFlat, point: screenPoint, maxAreaRatio: 0.85, screenArea: screenArea) {
                    debugLog("HIT (better): type=\(better.type), label=\(better.label.prefix(30))")
                    selectedNodeFrame = better.frame
                    let element = buildElementInfo(from: better)
                    onElementSelected?(element)
                    return
                }
            }
            debugLog("HIT (exact): type=\(hitNode.type), label=\(hitNode.label.prefix(30)), area=\(Int(hitRatio*100))%%")
            selectedNodeFrame = hitNode.frame
            let element = buildElementInfo(from: hitNode)
            onElementSelected?(element)
            return
        }

        // Fallback: find the smallest node that contains the point
        if let containing = findSmallestContainingNode(nodes: allFlat, point: screenPoint) {
            debugLog("HIT (smallest containing): type=\(containing.type), label=\(containing.label.prefix(30))")
            selectedNodeFrame = containing.frame
            let element = buildElementInfo(from: containing)
            onElementSelected?(element)
            return
        }

        // Last resort: closest node by center distance
        if let closest = findClosestNode(nodes: allFlat, point: screenPoint) {
            debugLog("HIT (closest): type=\(closest.type), label=\(closest.label.prefix(30))")
            selectedNodeFrame = closest.frame
            let element = buildElementInfo(from: closest)
            onElementSelected?(element)
            return
        }

        debugLog("NO HIT: no element found at point")
    }

    func inspectNode(_ node: AccessibilityNode) {
        selectedNodeFrame = node.frame
        let element = buildElementInfo(from: node)
        onElementSelected?(element)
    }

    /// Refresh the cached AX hierarchy in the background.
    func refreshAXCache() async {
        // Update permission status
        hasAccessibilityPermission = AXIsProcessTrusted()

        guard let udid = selectedDeviceUDID else { return }
        do {
            let nodes = try await simulator.accessibilityHierarchy(
                deviceUDID: udid,
                bundleID: ""
            )
            cachedNodes = nodes
            cacheTimestamp = Date()
            cachedWindowBounds = simulator.simulatorWindowContentBounds()
            debugLog("AX cache refreshed: \(nodes.count) top-level nodes, bounds=\(cachedWindowBounds.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil")")
        } catch {
            debugLog("AX cache refresh failed: \(error)")
        }
    }

    // MARK: - Element Building

    private func buildElementInfo(from node: AccessibilityNode) -> ElementInfo {
        let sourceMatch = sourceMapper?.findSource(for: node)
        let filePath = sourceMatch?.filePath ?? ""
        let lineNumber = sourceMatch?.lineNumber ?? 0

        let reader = SourceFileReader(projectPath: projectPath)
        var snippet = ""
        if !filePath.isEmpty, lineNumber > 0 {
            snippet = (try? reader.readSnippet(filePath: filePath, lineNumber: lineNumber)) ?? ""
        }

        let platform: PlatformType = node.type.contains("UI") ? .uiKit : .swiftUI

        // Build children summary (type + label for each direct child, max 10)
        let childSummaries: [String] = node.children.prefix(10).map { child in
            let childType = child.type.isEmpty ? "Unknown" : child.type
            if child.label.isEmpty {
                return childType
            }
            return "\(childType)(\"\(child.label.prefix(30))\")"
        }

        return ElementInfo(
            id: UUID(),
            platform: platform,
            componentName: node.type.isEmpty ? (node.label.isEmpty ? "Unknown" : node.label) : node.type,
            filePath: filePath,
            lineNumber: lineNumber,
            columnNumber: nil,
            codeSnippet: snippet,
            componentTree: buildTreePath(from: node),
            elementRect: ElementInfo.ElementRect(
                x: node.frame.origin.x,
                y: node.frame.origin.y,
                width: node.frame.size.width,
                height: node.frame.size.height
            ),
            tagName: node.type,
            textContent: node.label.isEmpty ? nil : node.label,
            timestamp: Date(),
            accessibilityIdentifier: node.identifier,
            childrenSummary: childSummaries
        )
    }

    private func buildTreePath(from node: AccessibilityNode) -> [String] {
        var path = [node.type.isEmpty ? node.label : node.type]
        for child in node.children {
            if !child.type.isEmpty {
                path.append(child.type)
                break
            }
        }
        return path
    }

    // MARK: - Hit Testing

    private func findNodeAtPoint(nodes: [AccessibilityNode], point: CGPoint) -> AccessibilityNode? {
        for node in nodes.reversed() {
            if node.frame.contains(point) {
                if let childHit = findNodeAtPoint(nodes: node.children, point: point) {
                    return childHit
                }
                return node
            }
        }
        return nil
    }

    private func flattenNodes(_ nodes: [AccessibilityNode]) -> [AccessibilityNode] {
        var result: [AccessibilityNode] = []
        for node in nodes {
            result.append(node)
            result.append(contentsOf: flattenNodes(node.children))
        }
        return result
    }

    /// Find the smallest node whose frame contains the point.
    /// If maxAreaRatio and screenArea are provided, skip elements larger than that ratio of the screen.
    private func findSmallestContainingNode(
        nodes: [AccessibilityNode],
        point: CGPoint,
        maxAreaRatio: Double = .infinity,
        screenArea: Double = 1
    ) -> AccessibilityNode? {
        let maxArea = maxAreaRatio == .infinity ? Double.infinity : screenArea * maxAreaRatio
        var best: AccessibilityNode?
        var bestArea = Double.infinity

        for node in nodes {
            guard node.frame.width > 0, node.frame.height > 0 else { continue }
            guard node.frame.contains(point) else { continue }

            let area = node.frame.width * node.frame.height
            guard area <= maxArea else { continue }
            if area < bestArea {
                bestArea = area
                best = node
            }
        }

        return best
    }

    /// Find the closest node by center distance.
    /// If maxAreaRatio and screenArea are provided, skip elements larger than that ratio.
    private func findClosestNode(
        nodes: [AccessibilityNode],
        point: CGPoint,
        maxAreaRatio: Double = .infinity,
        screenArea: Double = 1
    ) -> AccessibilityNode? {
        let maxArea = maxAreaRatio == .infinity ? Double.infinity : screenArea * maxAreaRatio
        var best: AccessibilityNode?
        var bestDistance = Double.infinity

        for node in nodes {
            guard node.frame.width > 0, node.frame.height > 0 else { continue }

            let area = node.frame.width * node.frame.height
            guard area <= maxArea else { continue }

            let centerX = node.frame.midX
            let centerY = node.frame.midY
            let dx = centerX - point.x
            let dy = centerY - point.y
            let distance = sqrt(dx * dx + dy * dy)

            // Prefer smaller elements when distances are similar
            if distance < bestDistance {
                bestDistance = distance
                best = node
            } else if abs(distance - bestDistance) < 20 {
                // Within 20pt, prefer the smaller element
                let bestNodeArea = (best?.frame.width ?? 0) * (best?.frame.height ?? 0)
                if area < bestNodeArea {
                    best = node
                }
            }
        }

        return best
    }

    /// Convert an AX screen-coordinate frame to display coordinates for the preview overlay.
    func convertFrameToDisplay(
        axFrame: CGRect,
        imageSize: CGSize,
        displaySize: CGSize
    ) -> CGRect? {
        guard let bounds = cachedWindowBounds,
              bounds.width > 0, bounds.height > 0
        else { return nil }

        // AX frame -> image coordinates
        let imgX = (axFrame.origin.x - bounds.origin.x) / bounds.width * imageSize.width
        let imgY = (axFrame.origin.y - bounds.origin.y) / bounds.height * imageSize.height
        let imgW = axFrame.width / bounds.width * imageSize.width
        let imgH = axFrame.height / bounds.height * imageSize.height

        // Image coordinates -> display coordinates
        let scaleX = displaySize.width / imageSize.width
        let scaleY = displaySize.height / imageSize.height

        return CGRect(
            x: imgX * scaleX,
            y: imgY * scaleY,
            width: imgW * scaleX,
            height: imgH * scaleY
        )
    }
}
