import Foundation
import AppKit

enum ArchiveRepository {
    static func loadSnapshot(root: URL) throws -> ArchiveSnapshot {
        let workspaceURL = root.appendingPathComponent("storages/workspace.json")
        let projectionURL = root.appendingPathComponent("storages/session_projcache.json")
        let workspace = try readJSONObject(at: workspaceURL, label: "Workspace 索引")
        let projection = try? readJSONObject(at: projectionURL, label: "会话摘要缓存")

        guard let global = workspace["global"] as? [String: Any],
              let archivedIds = global["archivedSessionIds"] as? [String] else {
            throw ArchiveManagerError.message("Workspace 索引中没有有效的 archivedSessionIds。")
        }

        var workspaceBySession: [String: ArchiveWorkspaceInfo] = [:]
        if let tables = workspace["tables"] as? [String: Any],
           let workspaces = tables["workspaces"] as? [String: Any] {
            for rawWorkspace in workspaces.values {
                guard let record = rawWorkspace as? [String: Any],
                      let sessionIds = record["sessionIds"] as? [String] else { continue }
                let title = record["title"] as? String ?? ""
                let path = record["path"] as? String ?? ""
                let info = ArchiveWorkspaceInfo(title: title, path: path)
                for id in sessionIds { workspaceBySession[id] = info }
            }
        }

        var projectionSessions: [String: Any] = [:]
        if let projection,
           let tables = projection["tables"] as? [String: Any],
           let sessions = tables["sessions"] as? [String: Any] {
            projectionSessions = sessions
        }
        let directories = sessionDirectoryMap(root: root)

        let items = archivedIds.map { id -> ArchivedConversation in
            let record = projectionSessions[id] as? [String: Any]
            let identity = record?["identity"] as? [String: Any]
            let rows = record?["rows"] as? [String: Any]
            let titleRecord = rows?["title"] as? [String: Any]
            let metadataRecord = rows?["sessionListMetadata"] as? [String: Any]
            let metadata = metadataRecord?["val"] as? [String: Any]
            let rawTitle = (titleRecord?["val"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let workspaceInfo = workspaceBySession[id]
            let cachedCwd = identity?["cwd"] as? String
            let directory = directories[id]
            let createdAt = dateFromMilliseconds(identity?["createdAt"])
            let updatedAt = dateFromMilliseconds(metadata?["lastPromptAt"]) ?? createdAt
            return ArchivedConversation(
                id: id,
                title: rawTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "未命名会话",
                workspaceTitle: workspaceInfo?.title,
                cwd: cachedCwd ?? workspaceInfo?.path,
                createdAt: createdAt,
                updatedAt: updatedAt,
                byteCount: directory.map(directoryByteCount) ?? 0,
                directoryURL: directory
            )
        }.sorted {
            let left = $0.updatedAt ?? $0.createdAt ?? .distantPast
            let right = $1.updatedAt ?? $1.createdAt ?? .distantPast
            if left != right { return left > right }
            return $0.id < $1.id
        }
        return ArchiveSnapshot(items: items, totalByteCount: items.reduce(0) { $0 + $1.byteCount })
    }

    static func restore(ids: [String], root: URL) throws -> URL {
        let workspaceURL = root.appendingPathComponent("storages/workspace.json")
        let originalData = try Data(contentsOf: workspaceURL)
        var workspace = try readJSONObject(data: originalData, label: "Workspace 索引")
        guard var global = workspace["global"] as? [String: Any],
              let archived = global["archivedSessionIds"] as? [String] else {
            throw ArchiveManagerError.message("Workspace 索引中没有有效的 archivedSessionIds。")
        }
        let targets = Set(ids)
        guard archived.contains(where: targets.contains) else {
            throw ArchiveManagerError.message("所选会话已不在归档列表中，请刷新后重试。")
        }
        global["archivedSessionIds"] = archived.filter { !targets.contains($0) }
        workspace["global"] = global
        let replacement = try jsonData(workspace)
        let backup = try createBackup(
            root: root, operation: "restore", ids: ids,
            workspaceData: originalData, projectionData: nil
        )
        do {
            try replacement.write(to: workspaceURL, options: .atomic)
        } catch {
            throw ArchiveManagerError.message("无法写入 Workspace 索引：\(error.localizedDescription)。原文件未被替换，备份位于 \(abbreviatedPath(backup.path))。")
        }
        return backup
    }

    static func delete(ids: [String], root: URL) throws -> (backup: URL, trashedCount: Int) {
        let fileManager = FileManager.default
        let workspaceURL = root.appendingPathComponent("storages/workspace.json")
        let projectionURL = root.appendingPathComponent("storages/session_projcache.json")
        let workspaceOriginalData = try Data(contentsOf: workspaceURL)
        var workspace = try readJSONObject(data: workspaceOriginalData, label: "Workspace 索引")
        guard var global = workspace["global"] as? [String: Any],
              let archived = global["archivedSessionIds"] as? [String] else {
            throw ArchiveManagerError.message("Workspace 索引中没有有效的 archivedSessionIds。")
        }

        let requested = Set(ids)
        let existing = archived.filter(requested.contains)
        guard !existing.isEmpty else {
            throw ArchiveManagerError.message("所选会话已不在归档列表中，请刷新后重试。")
        }
        let targets = Set(existing)
        global["archivedSessionIds"] = archived.filter { !targets.contains($0) }
        workspace["global"] = global

        if var tables = workspace["tables"] as? [String: Any],
           var workspaces = tables["workspaces"] as? [String: Any] {
            for (workspaceId, rawWorkspace) in workspaces {
                guard var record = rawWorkspace as? [String: Any],
                      let sessionIds = record["sessionIds"] as? [String] else { continue }
                record["sessionIds"] = sessionIds.filter { !targets.contains($0) }
                workspaces[workspaceId] = record
            }
            tables["workspaces"] = workspaces
            workspace["tables"] = tables
        }
        let workspaceReplacementData = try jsonData(workspace)

        var projectionOriginalData: Data?
        var projectionReplacementData: Data?
        if fileManager.fileExists(atPath: projectionURL.path) {
            let original = try Data(contentsOf: projectionURL)
            var projection = try readJSONObject(data: original, label: "会话摘要缓存")
            if var tables = projection["tables"] as? [String: Any],
               var sessions = tables["sessions"] as? [String: Any] {
                for id in targets { sessions.removeValue(forKey: id) }
                tables["sessions"] = sessions
                projection["tables"] = tables
            }
            projectionOriginalData = original
            projectionReplacementData = try jsonData(projection)
        }

        let backup = try createBackup(
            root: root, operation: "delete", ids: existing,
            workspaceData: workspaceOriginalData, projectionData: projectionOriginalData
        )

        let directories = sessionDirectoryMap(root: root)
        var moved: [(original: URL, trashed: URL)] = []
        do {
            for id in existing {
                guard let original = directories[id], fileManager.fileExists(atPath: original.path) else { continue }
                var resultingURL: NSURL?
                try fileManager.trashItem(at: original, resultingItemURL: &resultingURL)
                guard let trashed = resultingURL as URL? else {
                    throw ArchiveManagerError.message("“\(id)”已请求移到废纸篓，但系统没有返回新位置。")
                }
                moved.append((original, trashed))
            }
        } catch {
            let rollbackFailures = restoreMovedDirectories(moved)
            let suffix = rollbackFailures.isEmpty ? "" : "；另有日志恢复失败：\(rollbackFailures.joined(separator: "、"))"
            throw ArchiveManagerError.message("日志未能全部移到废纸篓：\(error.localizedDescription)\(suffix)")
        }

        do {
            try workspaceReplacementData.write(to: workspaceURL, options: .atomic)
            if let projectionReplacementData {
                try projectionReplacementData.write(to: projectionURL, options: .atomic)
            }
        } catch {
            try? workspaceOriginalData.write(to: workspaceURL, options: .atomic)
            if let projectionOriginalData {
                try? projectionOriginalData.write(to: projectionURL, options: .atomic)
            }
            let rollbackFailures = restoreMovedDirectories(moved)
            let suffix = rollbackFailures.isEmpty ? "" : "；另有日志恢复失败：\(rollbackFailures.joined(separator: "、"))"
            throw ArchiveManagerError.message("索引写入失败，已尝试回滚：\(error.localizedDescription)\(suffix)。备份位于 \(abbreviatedPath(backup.path))。")
        }
        return (backup, moved.count)
    }

    static func readJSONObject(at url: URL, label: String) throws -> [String: Any] {
        do {
            return try readJSONObject(data: Data(contentsOf: url), label: label)
        } catch let error as ArchiveManagerError {
            throw error
        } catch {
            throw ArchiveManagerError.message("无法读取\(label)：\(url.path)（\(error.localizedDescription)）")
        }
    }

    static func readJSONObject(data: Data, label: String) throws -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ArchiveManagerError.message("\(label)不是 JSON 对象。")
            }
            return object
        } catch let error as ArchiveManagerError {
            throw error
        } catch {
            throw ArchiveManagerError.message("\(label)格式无效：\(error.localizedDescription)")
        }
    }

    static func jsonData(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ArchiveManagerError.message("更新后的会话索引无法序列化。")
        }
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }

    static func createBackup(
        root: URL,
        operation: String,
        ids: [String],
        workspaceData: Data,
        projectionData: Data?
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = formatter.string(from: Date()) + "-" + UUID().uuidString.prefix(8)
        let directory = root
            .appendingPathComponent("backups/archive-manager", isDirectory: true)
            .appendingPathComponent(String(name), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try workspaceData.write(to: directory.appendingPathComponent("workspace.json"), options: .atomic)
            if let projectionData {
                try projectionData.write(to: directory.appendingPathComponent("session_projcache.json"), options: .atomic)
            }
            let manifest: [String: Any] = [
                "createdAt": ISO8601DateFormatter().string(from: Date()),
                "operation": operation,
                "sessionIds": ids,
            ]
            try jsonData(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
            return directory
        } catch {
            throw ArchiveManagerError.message("无法创建归档索引备份：\(error.localizedDescription)")
        }
    }

    static func sessionDirectoryMap(root: URL) -> [String: URL] {
        let fileManager = FileManager.default
        let sessionsRoot = root.appendingPathComponent("sessions", isDirectory: true)
        guard let cwdDirectories = try? fileManager.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }
        var result: [String: URL] = [:]
        for cwdDirectory in cwdDirectories {
            guard (try? cwdDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let sessionDirectories = try? fileManager.contentsOfDirectory(
                    at: cwdDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                  ) else { continue }
            for directory in sessionDirectories where directory.lastPathComponent.hasPrefix("session-") {
                guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                result[directory.lastPathComponent] = directory
            }
        }
        return result
    }

    static func directoryByteCount(_ directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    static func dateFromMilliseconds(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let milliseconds = number.doubleValue
        guard milliseconds.isFinite, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    static func restoreMovedDirectories(_ moved: [(original: URL, trashed: URL)]) -> [String] {
        var failures: [String] = []
        for pair in moved.reversed() {
            do {
                try FileManager.default.createDirectory(
                    at: pair.original.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: pair.trashed, to: pair.original)
            } catch {
                failures.append(pair.original.lastPathComponent)
            }
        }
        return failures
    }

    static func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }
        return path
    }
}
