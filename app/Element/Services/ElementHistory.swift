import Foundation

/// Tracks recently selected elements for quick re-access.
/// Keeps a fixed-size ring buffer of recent selections.
@MainActor
final class ElementHistory: ObservableObject {
    @Published private(set) var items: [ElementInfo] = []

    private let maxItems: Int

    init(maxItems: Int = 20) {
        self.maxItems = maxItems
    }

    func add(_ element: ElementInfo) {
        // Remove duplicate if same file+line already exists
        let filtered = items.filter {
            $0.filePath != element.filePath || $0.lineNumber != element.lineNumber
        }

        // Prepend new element, trim to max
        items = [element] + filtered.prefix(maxItems - 1)
    }

    func clear() {
        items = []
    }

    func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items = Array(items.enumerated().filter { $0.offset != index }.map { $0.element })
    }

    var isEmpty: Bool {
        items.isEmpty
    }
}
