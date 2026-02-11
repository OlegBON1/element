import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var projects: [ProjectConfig] = []
    @Published var selectedProjectID: UUID?
    @Published private(set) var selectedElement: ElementInfo?
    @Published private(set) var bridgeStatus: BridgeStatus = .disconnected
    @Published var inspectionEnabled: Bool = false
    @Published var selectedTemplateID: UUID?
    @Published var promptInstruction: String = ""

    let elementHistory = ElementHistory()

    private let projectsKey = "element.projects"

    var selectedProject: ProjectConfig? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    var selectedTemplate: PromptTemplate {
        guard let id = selectedTemplateID else {
            return PromptTemplate.defaultTemplate
        }
        return PromptTemplate.allDefaults.first { $0.id == id }
            ?? PromptTemplate.defaultTemplate
    }

    var renderedPrompt: String? {
        guard let element = selectedElement else { return nil }
        let template: PromptTemplate
        if selectedTemplateID != nil {
            template = selectedTemplate
        } else {
            template = PromptTemplate.bestTemplate(for: element)
        }
        return template.render(
            element: element,
            instruction: promptInstruction
        )
    }

    var canSendToClaudeCode: Bool {
        selectedElement != nil
    }

    var isBridgeReady: Bool {
        bridgeStatus.connection.isConnected && bridgeStatus.childAlive
    }

    // MARK: - Project Management

    func addProject(_ project: ProjectConfig) {
        projects = projects + [project]
        selectedProjectID = project.id
        saveProjects()
    }

    func removeProject(id: UUID) {
        projects = projects.filter { $0.id != id }
        if selectedProjectID == id {
            selectedProjectID = projects.first?.id
        }
        saveProjects()
    }

    func updateProject(_ updated: ProjectConfig) {
        projects = projects.map { $0.id == updated.id ? updated : $0 }
        saveProjects()
    }

    // MARK: - Element Selection

    func selectElement(_ element: ElementInfo) {
        selectedElement = element
        elementHistory.add(element)
    }

    func clearSelection() {
        selectedElement = nil
    }

    // MARK: - Bridge Status

    func updateBridgeStatus(_ status: BridgeStatus) {
        bridgeStatus = status
    }

    func setBridgeConnection(_ state: BridgeConnectionState) {
        bridgeStatus = bridgeStatus.withConnection(state)
    }

    // MARK: - Persistence

    func loadProjects() {
        guard let data = UserDefaults.standard.data(forKey: projectsKey),
              let decoded = try? JSONDecoder().decode([ProjectConfig].self, from: data)
        else { return }
        projects = decoded
        selectedProjectID = projects.first?.id
    }

    private func saveProjects() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: projectsKey)
    }
}
