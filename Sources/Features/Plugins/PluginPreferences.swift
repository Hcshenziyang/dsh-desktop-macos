import Foundation
import Combine

package final class PluginPreferences: ObservableObject {
    @Published package var simplifyPluginInventory: Bool { didSet { persist() } }
    private let defaults: UserDefaults
    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        simplifyPluginInventory = defaults.object(forKey: "simplifyPluginInventory") as? Bool ?? true
    }
    private func persist() { defaults.set(simplifyPluginInventory, forKey: "simplifyPluginInventory") }
}
