import Foundation
import Combine

package final class InspectorPreferences: ObservableObject {
    @Published package var captureModelRequests: Bool { didSet { persist() } }
    private let defaults: UserDefaults
    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        captureModelRequests = defaults.object(forKey: "captureModelRequests") as? Bool ?? true
    }
    private func persist() { defaults.set(captureModelRequests, forKey: "captureModelRequests") }
}
