import Foundation
import DSHCore

func pluginInventoryOutputURL() -> URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    return caches.appendingPathComponent("io.github.dramtea.dsh-desktop-community").appendingPathComponent("plugin-inventory.json")
}

func preparePluginInventoryPatch(moduleURL: URL? = nil, outputURL: URL? = nil) throws -> URL {
    let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let candidates = [moduleURL, Bundle.main.resourceURL?.appendingPathComponent("PluginInventory/plugin-inventory.mjs"),
                      sourceRoot.appendingPathComponent("Resources/PluginInventory/plugin-inventory.mjs")].compactMap { $0 }
    guard let module = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) else {
        throw PluginOperationError(message: "未找到插件状态观察模块。")
    }
    let output = outputURL ?? pluginInventoryOutputURL()
    let directory = output.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let patch = directory.appendingPathComponent("plugin-inventory.patch.yml")
    func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
    let contents = """
    - insert:
        - id: dsh-desktop-plugin-inventory
          name: \(quoted(module.path))
          config:
            outputPath: \(quoted(output.path))
    """ + "\n"
    try Data(contents.utf8).write(to: patch, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: patch.path)
    return patch
}


package final class PluginLaunchObserver {
    private let moduleURL: URL?
    private let outputURL: URL
    package init(moduleURL: URL? = nil, outputURL: URL? = nil) {
        self.moduleURL = moduleURL
        self.outputURL = outputURL ?? pluginInventoryOutputURL()
    }
    package func prepare() -> DSHLaunchPreparation {
        cleanUp()
        do {
            let patch = try preparePluginInventoryPatch(moduleURL: moduleURL, outputURL: outputURL)
            return DSHLaunchPreparation(arguments: ["--patch", patch.path])
        } catch {
            return DSHLaunchPreparation(messages: ["⚠️ 插件运行状态观察不可用：\(error.localizedDescription)"])
        }
    }
    package func cleanUp() { try? FileManager.default.removeItem(at: outputURL) }
}
