import Foundation
import Combine

package final class ActivityLog: ObservableObject {
    @Published package private(set) var text = ""
    private var lines: [String] = []
    package init() {}
    package func append(_ message: String) {
        lines.append(message)
        if lines.count > 4000 { lines.removeFirst(lines.count - 4000) }
        text = lines.joined(separator: "\n")
    }
    package func clear() { lines.removeAll(); text = "" }
}
