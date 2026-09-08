import Foundation
import CryptoKit

/// Markdown is the only editable file type. Every save compares the bytes read
/// by the editor with the current file before replacing it atomically.
struct MarkdownFile {
    static let limit = 2 * 1024 * 1024
    let files: ProjectFiles

    private func location(workspaceID: String, path: String) throws -> URL {
        guard ["md", "markdown"].contains((path as NSString).pathExtension.lowercased()) else {
            throw ProjectFileError.message("客户端只编辑 Markdown 文件。其他格式请用默认应用打开。")
        }
        let url = try files.resolve(workspaceID: workspaceID, relativePath: path)
        guard ["md", "markdown"].contains(url.pathExtension.lowercased()) else {
            throw ProjectFileError.message("此链接的目标不是 Markdown 文件。")
        }
        return url
    }

    private func bytes(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ProjectFileError.message("文件不存在或不是普通文件。") }
        guard (values.fileSize ?? Int.max) <= Self.limit else {
            throw ProjectFileError.message("此 Markdown 超过 2 MB，请使用默认应用打开。")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.limit + 1) ?? Data()
        guard data.count <= Self.limit else { throw ProjectFileError.message("文件过大，请使用默认应用打开。") }
        guard !data.contains(0), String(data: data, encoding: .utf8) != nil else {
            throw ProjectFileError.message("此文件不是 UTF-8 文本，请使用默认应用打开。")
        }
        return data
    }

    private func version(_ data: Data, at url: URL) -> String {
        var digest = SHA256()
        digest.update(data: Data(url.path.utf8)); digest.update(data: Data([0])); digest.update(data: data)
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func document(_ data: Data, at url: URL) -> [String: Any] {
        let payload = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(data.dropFirst(3)) : data
        let text = String(decoding: payload, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        return ["text": text, "version": version(data, at: url), "name": url.lastPathComponent]
    }

    func read(workspaceID: String, path: String) throws -> [String: Any] {
        let url = try location(workspaceID: workspaceID, path: path)
        return document(try bytes(at: url), at: url)
    }

    func save(workspaceID: String, path: String, text: String, expectedVersion: String) throws -> [String: Any] {
        guard text.utf8.count <= Self.limit, !text.contains("\0"), expectedVersion.count == 64 else {
            throw ProjectFileError.message("无法保存：内容过大、含无效字符，或文件版本无效。")
        }
        let url = try location(workspaceID: workspaceID, path: path)
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var outcome: Result<[String: Any], Error>?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            outcome = Result {
                // Re-resolve identity after coordination: a moved workspace or
                // changed link must not redirect a pending save to another file.
                guard try location(workspaceID: workspaceID, path: path) == url, coordinatedURL == url else {
                    throw ProjectFileError.message("文件位置已改变，请重新打开后编辑。")
                }
                let current = try bytes(at: url)
                guard version(current, at: url) == expectedVersion else {
                    throw ProjectFileError.message("文件已被其他应用或 Agent 修改，本次没有覆盖。你的草稿仍保留，请核对后重新读取文件。")
                }
                var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
                if String(decoding: current, as: UTF8.self).contains("\r\n") {
                    normalized = normalized.replacingOccurrences(of: "\n", with: "\r\n")
                }
                var data = Data(normalized.utf8)
                if current.starts(with: [0xEF, 0xBB, 0xBF]) { data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0) }
                guard data.count <= Self.limit else { throw ProjectFileError.message("文件超过 2 MB，无法保存。") }
                guard FileManager.default.isWritableFile(atPath: url.path) else {
                    throw ProjectFileError.message("此文件只读，请在其他应用中处理文件权限。")
                }
                // Foundation's atomic replacement retains existing file permissions.
                try data.write(to: url, options: .atomic)
                return document(data, at: url)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw ProjectFileError.message("无法协调文件访问，请稍后重试。") }
        return try outcome.get()
    }
}
