import Foundation

struct RequestInspectorResources {
    let moduleURL: URL
}

/// The inspector ships beside the app executable in release builds. The source
/// checkout fallback keeps `swift run` and local debug builds useful as well.
func requestInspectorResources() -> RequestInspectorResources? {
    var directories: [URL] = []
    if let resourceURL = Bundle.main.resourceURL {
        directories.append(resourceURL.appendingPathComponent("RequestInspector", isDirectory: true))
    }
    let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    directories.append(sourceRoot.appendingPathComponent("Resources/RequestInspector", isDirectory: true))

    for directory in directories {
        let module = directory.appendingPathComponent("request-inspector.mjs")
        if FileManager.default.isReadableFile(atPath: module.path) {
            return RequestInspectorResources(moduleURL: module)
        }
    }
    return nil
}

/// Ephemeral, user-private bridge between the DSH-side observer and SwiftUI.
/// It is intentionally kept out of ~/.dsh so it is not mistaken for a durable
/// session log or synced as user memory.
func requestInspectorOutputURL() -> URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    return caches
        .appendingPathComponent("io.github.dramtea.dsh-desktop-community", isDirectory: true)
        .appendingPathComponent("request-inspector.json")
}

private func yamlQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
}

/// Loader entry names are structural YAML fields and cannot use DSH's `!!js`
/// value expressions. Generate a tiny overlay with literal absolute paths so a
/// relocated app bundle still imports the correct module without touching the
/// user's profile files.
func prepareRequestInspectorPatch(moduleURL: URL, outputURL: URL) throws -> URL {
    let directory = outputURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let patchURL = directory.appendingPathComponent("request-inspector.patch.yml")
    let contents = """
    - insert:
        - id: dsh-desktop-request-inspector
          name: \(yamlQuoted(moduleURL.path))
          config:
            outputPath: \(yamlQuoted(outputURL.path))
            maxRequests: 32
            maxBytes: 50331648
    """ + "\n"
    try Data(contents.utf8).write(to: patchURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: patchURL.path)
    return patchURL
}
