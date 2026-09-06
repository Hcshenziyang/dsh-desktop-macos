import Foundation

package func dshHomeDirectoryURL() -> URL {
    let environmentHome = ProcessInfo.processInfo.environment["DSH_HOME"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if let environmentHome, !environmentHome.isEmpty {
        return URL(fileURLWithPath: expandedUserPath(environmentHome), isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".dsh", isDirectory: true)
}
