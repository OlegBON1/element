import SwiftUI

struct IOSPreviewView: View {
    let project: ProjectConfig

    @EnvironmentObject private var appState: AppState
    @StateObject private var inspectorService = IOSInspectorService()
    @StateObject private var mirror = ScreenMirrorService()
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            contentView
        }
        .onAppear {
            setupInspector()
        }
        .onChange(of: inspectorService.selectedDeviceUDID) { _, udid in
            if let udid {
                mirror.startCapture(deviceUDID: udid)
            } else {
                mirror.stopCapture()
            }
        }
        .onChange(of: appState.inspectionEnabled) { _, enabled in
            if enabled {
                inspectorService.enableInspection()
            } else {
                inspectorService.disableInspection()
            }
        }
        .onDisappear {
            mirror.stopCapture()
        }
        .task {
            // Periodically refresh AX cache while inspecting
            while !Task.isCancelled {
                if inspectorService.isInspecting {
                    await inspectorService.refreshAXCache()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            if !inspectorService.bootedDevices.isEmpty {
                Picker("Device", selection: $inspectorService.selectedDeviceUDID) {
                    ForEach(inspectorService.bootedDevices) { device in
                        Text(device.name).tag(Optional(device.udid))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }

            Spacer()

            if inspectorService.isInspecting && !inspectorService.hasAccessibilityPermission {
                Label("No AX Permission", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Grant Accessibility permission in System Settings → Privacy & Security → Accessibility")
            }

            if inspectorService.isInspecting {
                Label("Inspector", systemImage: "eye")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            Button {
                Task { await refreshDevices() }
            } label: {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .help("Refresh simulator devices")
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if inspectorService.isConnected {
            simulatorScreenView
        } else {
            disconnectedView
        }
    }

    // MARK: - Simulator Screen

    private var simulatorScreenView: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .controlBackgroundColor)

                if let frame = mirror.currentFrame {
                    let imageSize = frame.size
                    let scale = fitScale(
                        imageSize: imageSize,
                        containerSize: geometry.size
                    )
                    let displayWidth = imageSize.width * scale
                    let displayHeight = imageSize.height * scale

                    Image(nsImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displayWidth, height: displayHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                        .overlay {
                            let ds = CGSize(width: displayWidth, height: displayHeight)
                            ZStack(alignment: .topLeading) {
                                // Highlight selected element
                                if let axFrame = inspectorService.selectedNodeFrame,
                                   let rect = inspectorService.convertFrameToDisplay(
                                    axFrame: axFrame,
                                    imageSize: imageSize,
                                    displaySize: ds
                                   ) {
                                    elementHighlight(rect: rect)
                                }

                                // Click overlay for inspection
                                if inspectorService.isInspecting {
                                    inspectorClickOverlay(
                                        displaySize: ds,
                                        imageSize: imageSize
                                    )
                                }
                            }
                            .frame(width: displayWidth, height: displayHeight)
                        }
                } else if mirror.isCapturing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Capturing simulator screen...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    noFrameView
                }
            }
        }
    }

    private func elementHighlight(rect: CGRect) -> some View {
        Rectangle()
            .fill(Color.blue.opacity(0.15))
            .border(Color.blue, width: 2)
            .frame(width: max(rect.width, 2), height: max(rect.height, 2))
            .offset(x: rect.origin.x, y: rect.origin.y)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.15), value: rect.origin.x)
            .animation(.easeOut(duration: 0.15), value: rect.origin.y)
    }

    private func inspectorClickOverlay(
        displaySize: CGSize,
        imageSize: CGSize
    ) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: displaySize.width, height: displaySize.height)
            .onTapGesture { location in
                // Convert click position from display coordinates to image coordinates
                let scaleX = imageSize.width / displaySize.width
                let scaleY = imageSize.height / displaySize.height
                let imgX = location.x * scaleX
                let imgY = location.y * scaleY

                Task {
                    await inspectorService.inspectElementAtPoint(
                        x: imgX,
                        y: imgY,
                        imageSize: imageSize
                    )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.blue.opacity(0.5), lineWidth: 2)
            }
    }

    private func fitScale(imageSize: CGSize, containerSize: CGSize) -> CGFloat {
        let padding: CGFloat = 24
        let available = CGSize(
            width: containerSize.width - padding,
            height: containerSize.height - padding
        )
        let scaleW = available.width / max(imageSize.width, 1)
        let scaleH = available.height / max(imageSize.height, 1)
        return min(scaleW, scaleH, 1.0)
    }

    private var noFrameView: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Waiting for simulator frame...")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if let error = mirror.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
    }

    // MARK: - Disconnected

    private var disconnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No iOS Simulator Running")
                .font(.title3)
                .fontWeight(.medium)

            Text("Start an iOS Simulator with your app running,\nthen click Refresh to connect.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)

            Button("Refresh Devices") {
                Task { await refreshDevices() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func setupInspector() {
        inspectorService.configure(
            projectPath: project.path,
            onElementSelected: { element in
                appState.selectElement(element)
            }
        )

        Task {
            await refreshDevices()
            if let udid = inspectorService.selectedDeviceUDID {
                mirror.startCapture(deviceUDID: udid)
            }
        }
    }

    private func refreshDevices() async {
        isRefreshing = true
        await inspectorService.refreshDevices()
        isRefreshing = false
    }
}
