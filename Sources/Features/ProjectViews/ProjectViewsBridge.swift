import Foundation
import AppKit
import DSHCore

package final class ProjectViewsBridge {
    private let files: ProjectFiles
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "dsh.project-files", qos: .userInitiated)

    package init(dataRoot: URL? = nil, defaults: UserDefaults = .standard) {
        files = ProjectFiles(dataRoot: dataRoot ?? dshHomeDirectoryURL())
        self.defaults = defaults
    }

    /// Work stays off the UI thread; native actions and preference changes return to it.
    package func handle(_ body: Any, reply: @escaping (Any?, String?) -> Void) {
        guard let request = body as? [String: Any], let action = request["action"] as? String,
              let id = request["workspaceID"] as? String, !id.isEmpty else {
            reply(nil, "无效的项目请求。"); return
        }
        let path = request["path"] as? String ?? ""
        queue.async { [self] in
            do {
                var result: [String: Any] = [:]
                switch action {
                case "scope":
                    let root = try files.root(workspaceID: id)
                    result = ["root": root.path]
                case "mode":
                    guard ["folder", "traditional"].contains(request["mode"] as? String ?? "") else {
                        throw ProjectFileError.message("未知的视图。")
                    }
                    _ = try files.root(workspaceID: id)
                case "list":
                    result = try files.list(workspaceID: id, path: path, showHidden: request["showHidden"] as? Bool ?? false)
                case "preview": result = try files.preview(workspaceID: id, path: path)
                case "markdownRead": result = try MarkdownFile(files: files).read(workspaceID: id, path: path)
                case "markdownSave":
                    guard let text = request["text"] as? String, let version = request["version"] as? String else {
                        throw ProjectFileError.message("Markdown 保存请求不完整。")
                    }
                    result = try MarkdownFile(files: files).save(workspaceID: id, path: path, text: text, expectedVersion: version)
                case "open":
                    let url = try files.resolve(workspaceID: id, relativePath: path)
                    guard FileManager.default.fileExists(atPath: url.path) else { throw ProjectFileError.message("文件不存在或已移动。") }
                    DispatchQueue.main.async {
                        let opened = NSWorkspace.shared.open(url)
                        reply(opened ? ["ok": true] : nil, opened ? nil : "未找到可打开此文件的默认应用，请在 Finder 中选择应用。")
                    }
                    return
                case "openLink":
                    guard let value = request["url"] as? String, let url = URL(string: value),
                          ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else {
                        throw ProjectFileError.message("不支持此链接类型。")
                    }
                    _ = try files.root(workspaceID: id)
                    DispatchQueue.main.async {
                        let opened = NSWorkspace.shared.open(url)
                        reply(opened ? ["ok": true] : nil, opened ? nil : "无法打开此链接。")
                    }
                    return
                case "reveal":
                    let url = try files.resolve(workspaceID: id, relativePath: path)
                    DispatchQueue.main.async {
                        if path.isEmpty { NSWorkspace.shared.open(url) }
                        else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        reply(["ok": true], nil)
                    }
                    return
                default: throw ProjectFileError.message("不支持的项目操作。")
                }
                let response = result
                DispatchQueue.main.async { [self] in
                    let key = "project-view." + id
                    var value = response
                    if action == "mode" { defaults.set(request["mode"], forKey: key) }
                    if action == "scope" { value["mode"] = defaults.string(forKey: key) == "folder" ? "folder" : "traditional" }
                    reply(value, nil)
                }
            } catch {
                DispatchQueue.main.async { reply(nil, error.localizedDescription) }
            }
        }
    }
}
