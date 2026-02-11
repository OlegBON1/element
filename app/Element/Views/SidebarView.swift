import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingAddProject = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $appState.selectedProjectID) {
                Section("Projects") {
                    ForEach(appState.projects) { project in
                        ProjectRow(project: project)
                            .tag(project.id)
                            .contextMenu {
                                projectContextMenu(for: project)
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            if !appState.elementHistory.isEmpty {
                Divider()
                ElementHistoryView()
                    .frame(maxHeight: 200)
            }

            addProjectButton
        }
        .sheet(isPresented: $showingAddProject) {
            AddProjectSheet()
        }
    }

    private var addProjectButton: some View {
        Button {
            showingAddProject = true
        } label: {
            Label("Add Project", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func projectContextMenu(for project: ProjectConfig) -> some View {
        Button("Remove", role: .destructive) {
            appState.removeProject(id: project.id)
        }
    }
}

// MARK: - Project Row

private struct ProjectRow: View {
    let project: ProjectConfig

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: project.platform.iconName)
                .foregroundStyle(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body)
                    .lineLimit(1)

                Text(project.platform.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Project Sheet

struct AddProjectSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var path = ""
    @State private var url = "http://localhost:3000"
    @State private var platform: PlatformType = .web
    @State private var port: String = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Project Name", text: $name)
                    .focused($nameFieldFocused)

                Picker("Platform", selection: $platform) {
                    ForEach(PlatformType.allCases) { type in
                        Label(type.displayName, systemImage: type.iconName)
                            .tag(type)
                    }
                }

                HStack {
                    TextField("Project Path", text: $path)
                    Button("Browse…") {
                        browseForPath()
                    }
                }

                if platform == .web {
                    TextField("Preview URL", text: $url)
                }

                if platform == .reactNative {
                    TextField("Metro Port", text: $port)
                        .frame(width: 120)
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Project") { addProject() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || path.isEmpty)
            }
            .padding()
        }
        .frame(width: 460, height: 340)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                nameFieldFocused = true
            }
        }
    }

    private func addProject() {
        let project: ProjectConfig
        switch platform {
        case .web:
            project = .webProject(name: name, path: path, url: url)
        case .reactNative:
            let metroPort = Int(port) ?? 8081
            project = .reactNativeProject(name: name, path: path, port: metroPort)
        case .swiftUI, .uiKit:
            project = .iosProject(name: name, path: path)
        }
        appState.addProject(project)
        dismiss()
    }

    private func browseForPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the project root directory"

        if panel.runModal() == .OK, let selectedURL = panel.url {
            path = selectedURL.path
            if name.isEmpty {
                name = selectedURL.lastPathComponent
            }
        }
    }
}
