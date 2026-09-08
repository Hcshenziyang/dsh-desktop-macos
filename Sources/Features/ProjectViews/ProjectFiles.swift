import Foundation

enum ProjectFileError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// The existing DSH workspace registry remains the authority for project roots.
/// Relative paths are checked after resolving links. Markdown writes live in MarkdownFile.
struct ProjectFiles {
    let dataRoot: URL
    private let manager = FileManager.default
    static let previewLimit = 512 * 1024

    func root(workspaceID: String) throws -> URL {
        let data = try Data(contentsOf: dataRoot.appendingPathComponent("storages/workspace.json"))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tables = json["tables"] as? [String: Any],
              let workspaces = tables["workspaces"] as? [String: Any],
              let workspace = workspaces[workspaceID] as? [String: Any],
              let path = workspace["path"] as? String, path.hasPrefix("/") else {
            throw ProjectFileError.message("项目尚未保存或已移除，请重新选择项目。")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            throw ProjectFileError.message("项目文件夹不存在或暂时无法访问。")
        }
        return url
    }

    func resolve(workspaceID: String, relativePath: String) throws -> URL {
        try resolve(base: root(workspaceID: workspaceID), relativePath: relativePath)
    }

    private func resolve(base: URL, relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\0"),
              !relativePath.split(separator: "/").contains("..") else {
            throw ProjectFileError.message("只能浏览当前项目内的文件。")
        }
        let url = relativePath.isEmpty ? base : base.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path == base.path || url.path.hasPrefix(base.path == "/" ? "/" : base.path + "/") else {
            throw ProjectFileError.message("这个链接指向项目外，请通过 Finder 查看。")
        }
        return url
    }

    func list(workspaceID: String, path: String, showHidden: Bool) throws -> [String: Any] {
        let base = try root(workspaceID: workspaceID)
        let url = try resolve(base: base, relativePath: path)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
                                         .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
        // One level only: no recursion through large projects or dependencies.
        let urls = try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys),
                                                   options: showHidden ? [] : [.skipsHiddenFiles])
        guard urls.count <= 20_000 else {
            throw ProjectFileError.message("此目录超过 20,000 个项目，请在 Finder 中查看，或进入更小的目录。")
        }
        let entries: [[String: Any]] = urls.map { child in
            let values = try? child.resourceValues(forKeys: keys)
            let relative = path.isEmpty ? child.lastPathComponent : path + "/" + child.lastPathComponent
            let allowed = (try? resolve(base: base, relativePath: relative)) != nil
            let folder = values?.isDirectory == true && values?.isPackage != true
            return ["name": child.lastPathComponent, "path": relative, "directory": folder,
                    "link": values?.isSymbolicLink ?? false, "accessible": allowed,
                    "size": values?.fileSize ?? 0, "modified": (values?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000]
        }.sorted {
            let a = $0["directory"] as? Bool == true, b = $1["directory"] as? Bool == true
            if a != b { return a }
            return ($0["name"] as? String ?? "").localizedStandardCompare($1["name"] as? String ?? "") == .orderedAscending
        }
        return ["path": path, "entries": entries]
    }

    func preview(workspaceID: String, path: String) throws -> [String: Any] {
        let url = try resolve(workspaceID: workspaceID, relativePath: path)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { return ["kind": "unsupported"] }
        let ext = url.pathExtension.lowercased()
        let imageTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp"]
        let limit = imageTypes[ext] == nil ? Self.previewLimit : 8 * 1024 * 1024
        guard (values.fileSize ?? Int.max) <= limit else {
            return ["kind": "unsupported", "reason": "文件较大，请在其他应用中打开。"]
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { return ["kind": "unsupported", "reason": "文件较大，请在其他应用中打开。"] }
        if let mime = imageTypes[ext] {
            return ["kind": "image", "url": "data:\(mime);base64," + data.base64EncodedString()]
        }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            return ["kind": "unsupported", "reason": "此格式可通过 Finder 在其他应用中查看。"]
        }
        // HTML, Markdown and scripts are rendered as text, never evaluated.
        return ["kind": "text", "text": text]
    }
}
