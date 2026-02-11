import Foundation

struct ProjectConfig: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let platform: PlatformType
    let url: String
    let port: Int?

    func withName(_ name: String) -> ProjectConfig {
        ProjectConfig(
            id: id,
            name: name,
            path: path,
            platform: platform,
            url: url,
            port: port
        )
    }

    func withURL(_ url: String) -> ProjectConfig {
        ProjectConfig(
            id: id,
            name: name,
            path: path,
            platform: platform,
            url: url,
            port: port
        )
    }

    var previewURL: URL? {
        URL(string: url)
    }

    var displayURL: String {
        url.isEmpty ? "No URL configured" : url
    }

    static func webProject(name: String, path: String, url: String) -> ProjectConfig {
        ProjectConfig(
            id: UUID(),
            name: name,
            path: path,
            platform: .web,
            url: url,
            port: nil
        )
    }

    static func reactNativeProject(name: String, path: String, port: Int = 8081) -> ProjectConfig {
        ProjectConfig(
            id: UUID(),
            name: name,
            path: path,
            platform: .reactNative,
            url: "http://localhost:\(port)",
            port: port
        )
    }

    static func iosProject(name: String, path: String) -> ProjectConfig {
        ProjectConfig(
            id: UUID(),
            name: name,
            path: path,
            platform: .swiftUI,
            url: "",
            port: nil
        )
    }
}
