import Foundation

enum PlatformType: String, Codable, CaseIterable, Identifiable {
    case web
    case reactNative
    case swiftUI
    case uiKit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .web: return "Web (React/Next.js)"
        case .reactNative: return "React Native"
        case .swiftUI: return "SwiftUI"
        case .uiKit: return "UIKit"
        }
    }

    var iconName: String {
        switch self {
        case .web: return "globe"
        case .reactNative: return "iphone"
        case .swiftUI: return "swift"
        case .uiKit: return "apps.iphone"
        }
    }
}
