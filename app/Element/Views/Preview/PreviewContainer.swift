import SwiftUI

struct PreviewContainer: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if let project = appState.selectedProject {
                previewForPlatform(project)
            } else {
                placeholderView
            }
        }
    }

    @ViewBuilder
    private func previewForPlatform(_ project: ProjectConfig) -> some View {
        switch project.platform {
        case .web:
            WebPreviewView(project: project)
        case .reactNative:
            RNPreviewView(project: project)
        case .swiftUI, .uiKit:
            IOSPreviewView(project: project)
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Select a project to preview")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Unsupported Platform Placeholder

private struct UnsupportedPlatformView: View {
    let platform: PlatformType

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: platform.iconName)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("\(platform.displayName) Preview")
                .font(.title3)
                .fontWeight(.medium)

            Text("Coming soon. This platform will be supported in a future update.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
