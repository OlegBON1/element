import Foundation
import WebKit

struct SDKMessage: Codable {
    let type: String
    let payload: SDKPayload
}

enum SDKPayload: Codable {
    case elementSelected(SDKElementPayload)
    case notification(SDKNotificationPayload)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let element = try? container.decode(SDKElementPayload.self),
           !element.componentName.isEmpty {
            self = .elementSelected(element)
        } else {
            self = .notification(try container.decode(SDKNotificationPayload.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .elementSelected(let el): try container.encode(el)
        case .notification(let n): try container.encode(n)
        }
    }
}

struct SDKElementPayload: Codable {
    let componentName: String
    let filePath: String
    let lineNumber: Int
    let columnNumber: Int?
    let componentTree: [String]
    let elementRect: SDKRect
    let tagName: String
    let textContent: String?
}

struct SDKRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct SDKNotificationPayload: Codable {
    let message: String
}

final class WebMessageHandler: NSObject, WKScriptMessageHandler {
    private let onElementSelected: (SDKElementPayload) -> Void
    private let onNotification: (String, String) -> Void

    init(
        onElementSelected: @escaping (SDKElementPayload) -> Void,
        onNotification: @escaping (String, String) -> Void
    ) {
        self.onElementSelected = onElementSelected
        self.onNotification = onNotification
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let jsonString = message.body as? String,
              let data = jsonString.data(using: .utf8)
        else { return }

        do {
            let sdkMessage = try JSONDecoder().decode(SDKMessage.self, from: data)

            switch sdkMessage.type {
            case "elementSelected":
                if case .elementSelected(let element) = sdkMessage.payload {
                    onElementSelected(element)
                }
            case "inspectorEnabled", "inspectorDisabled", "error":
                if case .notification(let notification) = sdkMessage.payload {
                    onNotification(sdkMessage.type, notification.message)
                }
            default:
                break
            }
        } catch {
            onNotification("error", "Failed to decode SDK message: \(error.localizedDescription)")
        }
    }
}
