import Foundation

enum BridgeConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var iconName: String {
        switch self {
        case .disconnected: return "circle.fill"
        case .connecting: return "circle.dotted"
        case .connected: return "circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .disconnected: return "gray"
        case .connecting: return "yellow"
        case .connected: return "green"
        case .error: return "red"
        }
    }
}

struct BridgeStatus: Equatable {
    let connection: BridgeConnectionState
    let idle: Bool
    let queueLength: Int
    let childAlive: Bool

    static let disconnected = BridgeStatus(
        connection: .disconnected,
        idle: false,
        queueLength: 0,
        childAlive: false
    )

    func withConnection(_ state: BridgeConnectionState) -> BridgeStatus {
        BridgeStatus(
            connection: state,
            idle: idle,
            queueLength: queueLength,
            childAlive: childAlive
        )
    }
}
