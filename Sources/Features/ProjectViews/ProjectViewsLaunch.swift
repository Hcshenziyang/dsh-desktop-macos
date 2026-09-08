import Foundation
import DSHCore

/// A temporary overlay loads the client adapter without changing the user's DSH profile.
package final class ProjectViewsLaunch {
    private var directory: URL?
    package init() {}

    package func prepare() -> DSHLaunchPreparation {
        cleanUp()
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("ProjectViews/project-views-host.mjs"),
                          sourceRoot.appendingPathComponent("Resources/ProjectViews/project-views-host.mjs")].compactMap { $0 }
        guard let module = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) else {
            return DSHLaunchPreparation(messages: ["⚠️ 文件夹视图资源缺失，继续使用传统视图"])
        }
        do {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-project-views-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            directory = temporary
            let patch = temporary.appendingPathComponent("project-views.yml")
            let quotedPath = "'" + module.path.replacingOccurrences(of: "'", with: "''") + "'"
            try Data("- insert:\n    - id: dsh-desktop-project-views\n      name: \(quotedPath)\n".utf8).write(to: patch, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: patch.path)
            return DSHLaunchPreparation(arguments: ["--patch", patch.path], messages: ["已启用项目文件夹视图"])
        } catch {
            cleanUp()
            return DSHLaunchPreparation(messages: ["⚠️ 文件夹视图未能加载：\(error.localizedDescription)"])
        }
    }
    package func cleanUp() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }
}
