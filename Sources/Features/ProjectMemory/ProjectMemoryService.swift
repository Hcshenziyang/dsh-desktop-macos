import Foundation
import DSHCore

/// Authenticated transport to the live memory domain; no second memory store.
package final class ProjectMemoryService {
    private let token = UUID().uuidString + UUID().uuidString
    private var launchDirectory: URL?
    private let session: URLSession
    package init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpShouldSetCookies = false
        config.urlCache = nil
        session = URLSession(configuration: config)
    }
    package func prepare() -> DSHLaunchPreparation {
        cleanUp()
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/ProjectMemory/host.mjs")
        let paths = [Bundle.main.resourceURL?.appendingPathComponent("ProjectMemory/host.mjs"), source].compactMap { $0 }
        guard let module = paths.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) else {
            return DSHLaunchPreparation(messages: ["⚠️ 项目记忆资源缺失"])
        }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-project-memory-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            launchDirectory = directory
            let patch = directory.appendingPathComponent("tools.yml")
            let value: [[String: Any]] = [["insert": [["id": "dsh-desktop-project-memory", "name": module.path,
                "config": ["token": token]]]]]
            try JSONSerialization.data(withJSONObject: value).write(to: patch, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: patch.path)
            return DSHLaunchPreparation(arguments: ["--patch", patch.path], messages: ["已启用项目记忆查看与编辑"])
        } catch {
            cleanUp()
            return DSHLaunchPreparation(messages: ["⚠️ 项目记忆启动准备失败：\(error.localizedDescription)"])
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
            reply(nil, "无效的本机项目记忆请求。"); return
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("dsh-desktop/project-memory/v1"))
        request.httpMethod = "POST"; request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        session.dataTask(with: request) { data, response, error in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let code = (response as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                if code == 200, let value = json?["value"] { reply(value, nil) }
                else if code == 403 || code == 404 {
                    reply(nil, "项目记忆尚未连接，请从本客户端重新启动 DSH 服务。")
                } else { reply(nil, json?["error"] as? String ?? error?.localizedDescription ?? "项目记忆暂不可用，请稍后重试。") }
            }
        }.resume()
    }
}
