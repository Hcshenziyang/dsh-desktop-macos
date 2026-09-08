import Foundation
import DSHCore

/// The DSH extension is the single writer. Native code transports authenticated
/// requests; it never maintains a second copy of todos, notes or schedules.
package final class WorkspaceToolsService {
    private let token = UUID().uuidString + UUID().uuidString
    private let dataRoot: URL
    private var launchDirectory: URL?
    private let session: URLSession
    package init(dataRoot: URL? = nil) {
        self.dataRoot = dataRoot ?? dshHomeDirectoryURL()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpShouldSetCookies = false
        config.urlCache = nil
        session = URLSession(configuration: config)
    }
    package func prepare() -> DSHLaunchPreparation {
        cleanUp()
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/WorkspaceTools/host.mjs")
        let paths = [Bundle.main.resourceURL?.appendingPathComponent("WorkspaceTools/host.mjs"), source].compactMap { $0 }
        guard let module = paths.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) else {
            return DSHLaunchPreparation(messages: ["⚠️ 工作区工具资源缺失"])
        }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-workspace-tools-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            launchDirectory = directory
            let patch = directory.appendingPathComponent("tools.yml")
            let value: [[String: Any]] = [["insert": [["id": "dsh-desktop-workspace-tools", "name": module.path,
                "config": ["token": token, "storagePath": dataRoot.appendingPathComponent("desktop/workspace-tools.json").path]]]]]
            try JSONSerialization.data(withJSONObject: value).write(to: patch, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: patch.path)
            return DSHLaunchPreparation(arguments: ["--patch", patch.path], messages: ["已启用工作区待办、便签与定时任务"])
        } catch {
            cleanUp()
            return DSHLaunchPreparation(messages: ["⚠️ 工作区工具启动准备失败：\(error.localizedDescription)"])
        }
    }
    package func cleanUp() {
        if let launchDirectory { try? FileManager.default.removeItem(at: launchDirectory) }
        launchDirectory = nil
    }
    package func handle(_ body: Any, baseURL: URL, reply: @escaping (Any?, String?) -> Void) {
        guard ["127.0.0.1", "localhost", "::1", "[::1]"].contains(baseURL.host ?? ""),
              let value = body as? [String: Any], JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value), data.count <= 200_000 else {
            reply(nil, "无效的本机工作区工具请求。"); return
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("dsh-desktop/workspace-tools/v1"))
        request.httpMethod = "POST"; request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        session.dataTask(with: request) { data, response, error in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let code = (response as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                if code == 200, let value = json?["value"] { reply(value, nil) }
                else if code == 403 || code == 404 {
                    reply(nil, "工作区工具尚未连接，请从本客户端重新启动 DSH 服务。")
                } else { reply(nil, json?["error"] as? String ?? error?.localizedDescription ?? "工作区工具暂不可用，请稍后重试。") }
            }
        }.resume()
    }
}
