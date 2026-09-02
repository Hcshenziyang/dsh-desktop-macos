import Foundation
import SwiftUI
import AppKit

// MARK: - 归档会话数据

// 一条已经归档的对话
struct ArchivedConversation: Identifiable, Hashable {
    let id: String // 对话唯一id
    let title: String // 对话标题
    let workspaceTitle: String? // 所属工作区名称（按项目分类的项目概念）
    let cwd: String? // 对话当时所在的项目目录
    let createdAt: Date?  // 创建时间
    let updatedAt: Date? // 更新时间
    let byteCount: Int64 // 对话日志占用的字节数
    let directoryURL: URL? //对话日志目录，找不到为nil
}

// 读档时内部辅助数据，私有
private struct ArchiveWorkspaceInfo {
    let title: String // 工作区名称
    let path: String // 工作区路径
}

// 一次归档扫描完整结果，私有
private struct ArchiveSnapshot {
    let items: [ArchivedConversation] // 扫描到的所有归档对话
    let totalByteCount: Int64 // 所有归档日志大小
}

// 错误类型
private enum ArchiveManagerError: LocalizedError {
    case message(String) // 错误消息

    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}

/// DSH 目前只提供“归档（隐藏）”，没有取消归档或删除接口。
/// 该管理器在服务停止时维护 DSH 的本地 JSON 索引，并把删除的日志目录移到废纸篓。
final class ArchiveStore: ObservableObject {
    @Published private(set) var items: [ArchivedConversation] = []
    @Published private(set) var totalByteCount: Int64 = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    let dataRootURL: URL

    init() {
        // 当前dsh根目录
        dataRootURL = dshHomeDirectoryURL()
    }

    // 路径拼接优化显示
    var displayDataRoot: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = dataRootURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }
        return path
    }

    //
    func reload() {
        guard !isLoading, !isBusy else { return }
        isLoading = true
        errorMessage = nil
        let root = dataRootURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let snapshot = try Self.loadSnapshot(root: root)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.items = snapshot.items
                    self.totalByteCount = snapshot.totalByteCount
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.items = []
                    self.totalByteCount = 0
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func restore(_ conversation: ArchivedConversation, servicePort: Int) {
        perform(servicePort: servicePort) {
            let backup = try Self.restore(ids: [conversation.id], root: self.dataRootURL)
            return "已恢复“\(conversation.title)”；索引备份：\(Self.abbreviatedPath(backup.path))"
        }
    }

    func delete(_ conversation: ArchivedConversation, servicePort: Int) {
        perform(servicePort: servicePort) {
            let result = try Self.delete(ids: [conversation.id], root: self.dataRootURL)
            return "已将“\(conversation.title)”移到废纸篓；索引备份：\(Self.abbreviatedPath(result.backup.path))"
        }
    }

    func deleteAll(servicePort: Int) {
        let ids = items.map(\.id)
        guard !ids.isEmpty else { return }
        perform(servicePort: servicePort) {
            let result = try Self.delete(ids: ids, root: self.dataRootURL)
            return "已清理 \(ids.count) 条归档会话（\(result.trashedCount) 个日志目录已移到废纸篓）；索引备份：\(Self.abbreviatedPath(result.backup.path))"
        }
    }

    private func perform(servicePort: Int, operation: @escaping () throws -> String) {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = nil
        errorMessage = nil
        let root = dataRootURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard listeningPid(port: servicePort) == nil else {
                    throw ArchiveManagerError.message("DSH 服务仍在监听端口 \(servicePort)。请先停止服务，避免运行中的进程覆盖会话索引。")
                }
                let message = try operation()
                let snapshot = try Self.loadSnapshot(root: root)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.items = snapshot.items
                    self.totalByteCount = snapshot.totalByteCount
                    self.isBusy = false
                    self.statusMessage = message
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private static func loadSnapshot(root: URL) throws -> ArchiveSnapshot {
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

    private static func restore(ids: [String], root: URL) throws -> URL {
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

    private static func delete(ids: [String], root: URL) throws -> (backup: URL, trashedCount: Int) {
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

    private static func readJSONObject(at url: URL, label: String) throws -> [String: Any] {
        do {
            return try readJSONObject(data: Data(contentsOf: url), label: label)
        } catch let error as ArchiveManagerError {
            throw error
        } catch {
            throw ArchiveManagerError.message("无法读取\(label)：\(url.path)（\(error.localizedDescription)）")
        }
    }

    private static func readJSONObject(data: Data, label: String) throws -> [String: Any] {
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

    private static func jsonData(_ object: [String: Any]) throws -> Data {
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

    private static func createBackup(
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

    private static func sessionDirectoryMap(root: URL) -> [String: URL] {
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

    private static func directoryByteCount(_ directory: URL) -> Int64 {
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

    private static func dateFromMilliseconds(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let milliseconds = number.doubleValue
        guard milliseconds.isFinite, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private static func restoreMovedDirectories(_ moved: [(original: URL, trashed: URL)]) -> [String] {
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

    private static func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }
        return path
    }
}

// MARK: - 归档管理

struct ArchiveManagerView: View {
    @StateObject private var store = ArchiveStore()
    @ObservedObject private var mgr = Manager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var dialog: ThemeDialogDescriptor?

    private var serviceActive: Bool {
        mgr.ownsProcess || mgr.state.portActive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("归档管理").font(.title2).bold()
                    Text("数据目录：\(store.displayDataRoot)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button(action: { store.reload() }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading || store.isBusy)
            }

            if serviceActive {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("管理前需要停止 DSH 服务").fontWeight(.medium)
                        Text("运行中的 DSH 会把内存状态重新写回索引，因此恢复和删除按钮暂时不可用。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if mgr.ownsProcess {
                        Button("停止服务") { mgr.stop() }
                            .disabled(mgr.state == .stopping)
                    } else if case .externalRunning(let pid) = mgr.state {
                        Button("停止外部实例") { presentStopExternalDialog(pid: pid) }
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                    Text("DSH 服务已停止，可以安全管理归档。")
                        .font(.callout)
                    Spacer()
                    if mgr.canStart {
                        Button("启动 DSH") { mgr.start() }
                    }
                }
            }

            GroupBox {
                ZStack {
                    if store.isLoading {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("正在读取归档会话…").foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if store.items.isEmpty {
                        VStack(spacing: 9) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 34))
                                .foregroundColor(.secondary)
                            Text("暂无归档会话").font(.headline)
                            Text("DSH 中归档的会话会显示在这里。")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(store.items) { conversation in
                            archiveRow(conversation)
                        }
                        .listStyle(.inset)
                    }

                    if store.isBusy {
                        Color.black.opacity(0.08)
                        ProgressView("正在更新归档…")
                            .padding(14)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                }
                .frame(minHeight: 360)
            } label: {
                Label(archiveSummary, systemImage: "tray.full")
            }

            if let error = store.errorMessage {
                ThemedStatusBanner(message: error, tone: .danger)
            } else if let status = store.statusMessage {
                ThemedStatusBanner(message: status, tone: .success)
            }

            Text("“恢复”只取消隐藏标记；“永久删除”会先备份索引，再将日志目录移到 macOS 废纸篓。清空废纸篓后日志才不可恢复。")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button(role: .destructive) {
                    presentDeleteAllDialog()
                } label: {
                    Label("清空全部归档", systemImage: "trash")
                }
                .disabled(store.items.isEmpty || serviceActive || store.isBusy)

                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 760)
        .frame(minHeight: 570)
        .background(ThemeWindowBackground())
        .onAppear { store.reload() }
        .themedDialog(item: $dialog)
    }

    private var archiveSummary: String {
        let size = ByteCountFormatter.string(fromByteCount: store.totalByteCount, countStyle: .file)
        return "已归档 \(store.items.count) 条 · 日志 \(size)"
    }

    private func presentDeleteDialog(_ conversation: ArchivedConversation) {
        dialog = ThemeDialogDescriptor(
            title: "永久删除这条归档？",
            message: "“\(conversation.title)”的日志将移到废纸篓，并从 DSH 索引中移除。操作前会自动备份索引。",
            systemImage: "trash.fill",
            tone: .danger,
            primaryTitle: "移到废纸篓",
            primaryRole: .destructive,
            primaryAction: { store.delete(conversation, servicePort: mgr.port) }
        )
    }

    private func presentDeleteAllDialog() {
        let count = store.items.count
        dialog = ThemeDialogDescriptor(
            title: "清空全部归档？",
            message: "将从 DSH 索引中移除 \(count) 条归档，并把找到的日志目录移到废纸篓。操作前会自动备份索引。",
            systemImage: "trash.slash.fill",
            tone: .danger,
            primaryTitle: "清空归档",
            primaryRole: .destructive,
            primaryAction: { store.deleteAll(servicePort: mgr.port) }
        )
    }

    private func presentStopExternalDialog(pid: Int32) {
        dialog = ThemeDialogDescriptor(
            title: "停止外部 DSH 实例？",
            message: "将向不是由本客户端启动的 dsh 进程（pid \(pid)）发送终止信号。",
            systemImage: "exclamationmark.octagon.fill",
            tone: .danger,
            primaryTitle: "停止",
            primaryRole: .destructive,
            primaryAction: { mgr.killExternal() }
        )
    }

    @ViewBuilder
    private func archiveRow(_ conversation: ArchivedConversation) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundColor(.secondary)
                .frame(width: 20, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .fontWeight(.medium)
                    .lineLimit(2)
                if let cwd = conversation.cwd, !cwd.isEmpty {
                    Text(cwd)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 8) {
                    Text(conversation.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if let date = conversation.updatedAt ?? conversation.createdAt {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    }
                    Text(ByteCountFormatter.string(fromByteCount: conversation.byteCount, countStyle: .file))
                    if conversation.directoryURL == nil {
                        Text("未找到 JSONL 日志").foregroundColor(.orange)
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                store.restore(conversation, servicePort: mgr.port)
            } label: {
                Label("恢复", systemImage: "arrow.uturn.backward")
            }
            .disabled(serviceActive || store.isBusy)

            Button(role: .destructive) {
                presentDeleteDialog(conversation)
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(serviceActive || store.isBusy)
        }
        .padding(.vertical, 5)
    }
}
