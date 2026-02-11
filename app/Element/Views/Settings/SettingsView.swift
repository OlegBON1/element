import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            TemplateSettingsView()
                .tabItem {
                    Label("Templates", systemImage: "doc.text")
                }

            BridgeSettingsView()
                .tabItem {
                    Label("Bridge", systemImage: "network")
                }
        }
        .frame(width: 520, height: 400)
    }
}

// MARK: - General Settings

private struct GeneralSettingsView: View {
    @AppStorage("bridgeAutoStart") private var bridgeAutoStart = true
    @AppStorage("inspectOnStart") private var inspectOnStart = false
    @AppStorage("showNotifications") private var showNotifications = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Auto-start bridge on launch", isOn: $bridgeAutoStart)
                Toggle("Enable inspection on project open", isOn: $inspectOnStart)
            }

            Section("Notifications") {
                Toggle("Show element selection notifications", isOn: $showNotifications)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Template Settings

private struct TemplateSettingsView: View {
    @State private var selectedTemplate: PromptTemplate = .defaultTemplate
    @State private var editedTemplate: String = PromptTemplate.defaultTemplate.template

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Template", selection: $selectedTemplate) {
                ForEach(PromptTemplate.allDefaults) { tmpl in
                    Text(tmpl.name).tag(tmpl)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedTemplate) { _, newValue in
                editedTemplate = newValue.template
            }

            Text("Available variables:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(templateVariables, id: \.self) { variable in
                        Text(variable)
                            .font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            TextEditor(text: $editedTemplate)
                .font(.system(.body, design: .monospaced))
                .padding(4)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.separator, lineWidth: 1)
                )
        }
        .padding()
    }

    private var templateVariables: [String] {
        [
            "{{componentName}}",
            "{{filePath}}",
            "{{lineNumber}}",
            "{{codeSnippet}}",
            "{{componentTree}}",
            "{{tagName}}",
            "{{textContent}}",
            "{{instruction}}",
        ]
    }
}

// MARK: - Bridge Settings

private struct BridgeSettingsView: View {
    @AppStorage("bridgeHost") private var host = "127.0.0.1"
    @AppStorage("bridgePort") private var port = 9999
    @AppStorage("bridgeParanoid") private var paranoidMode = false

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Host", text: $host)
                TextField("Port", value: $port, format: .number)
                    .frame(width: 120)
            }

            Section("Advanced") {
                Toggle("Paranoid mode (don't auto-submit)", isOn: $paranoidMode)

                Text("In paranoid mode, prompts are typed but not submitted. You must press Enter manually in Claude Code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
