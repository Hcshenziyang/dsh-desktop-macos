import Foundation

/// Feature-owned launch additions are assembled by App, never discovered by the runtime.
package struct DSHLaunchPreparation {
    package var arguments: [String]
    package var messages: [String]
    package init(arguments: [String] = [], messages: [String] = []) {
        self.arguments = arguments
        self.messages = messages
    }
}

/// Only the runtime can issue a permit to operate during maintenance.
package struct DSHMaintenanceToken: Equatable {
    private let id = UUID()
    internal init() {}
}
