import SwiftUI
import AppKit
@preconcurrency import WebKit
import ServiceManagement
import Darwin

// MARK: - 小工具函数

/// 执行一条外部命令并返回合并后的 stdout/stderr
func shellOut(_ path: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 查询监听某个 TCP 端口的进程 PID
func listeningPid(port: Int) -> Int32? {
    guard let out = shellOut("/usr/sbin/lsof", ["-tiTCP:\(port)", "-sTCP:LISTEN"]) else { return nil }
    guard let first = out.split(separator: "\n").first, let pid = Int32(first) else { return nil }
    return pid
}

/// 查询进程的命令行
func commandOf(pid: Int32) -> String {
    shellOut("/bin/ps", ["-p", "\(pid)", "-o", "command="]) ?? ""
}

/// 对服务做一次真实 HTTP 健康检查：收到任何 HTTP 响应（2xx/3xx/4xx/5xx）都说明服务活着，
/// 而不仅仅是 TCP 端口连通。连接被拒 / 超时 / 挂死无响应 → 返回 false。
/// 用于区分「健康的 dsh 实例」与「残留的僵尸进程（占着端口但不响应）」。
func isHttpAlive(_ host: String, _ port: Int, timeout: TimeInterval = 2.0) -> Bool {
    let name = host.isEmpty ? "127.0.0.1" : host
    guard let url = URL(string: "http://\(name):\(port)/") else { return false }
    var req = URLRequest(url: url)
    req.timeoutInterval = timeout
    req.cachePolicy = .reloadIgnoringLocalCacheData
    let sem = DispatchSemaphore(value: 0)
    var alive = false
    let task = URLSession.shared.dataTask(with: req) { _, resp, _ in
        if let r = resp as? HTTPURLResponse {
            alive = (100...599).contains(r.statusCode)
        }
        sem.signal()
    }
    task.resume()
    _ = sem.wait(timeout: .now() + timeout + 1.0)
    task.cancel()
    return alive
}

/// 常见 dsh 可执行文件候选位置（按优先级）
func dshCandidates() -> [String] {
    var list: [String] = []
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    // 稳定安装位置（不受 npm/npx 缓存清理影响）
    let stable = home + "/.dsh/app/node_modules/.bin/dsh"
    if FileManager.default.isExecutableFile(atPath: stable) {
        list.append(stable)
    }
    let npxRoot = home + "/.npm/_npx"
    if let dirs = try? FileManager.default.contentsOfDirectory(atPath: npxRoot) {
        var bins: [(path: String, date: Date)] = []
        for d in dirs {
            let b = npxRoot + "/" + d + "/node_modules/.bin/dsh"
            guard FileManager.default.isExecutableFile(atPath: b) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: b)
            let date = (attrs?[.modificationDate] as? Date) ?? .distantPast
            bins.append((b, date))
        }
        list += bins.sorted { $0.date > $1.date }.map { $0.path }
    }
    list += [
        "/opt/homebrew/bin/dsh",
        "/usr/local/bin/dsh",
        home + "/.npm-global/bin/dsh",
        "/usr/bin/dsh",
        "/bin/dsh",
    ]
    return list
}

/// 解析 dsh 路径：优先用户保存的，其次自动探测
func resolveDshPath() -> String {
    if let stored = UserDefaults.standard.string(forKey: "dshPath"),
       FileManager.default.isExecutableFile(atPath: stored) {
        return stored
    }
    for c in dshCandidates() where FileManager.default.isExecutableFile(atPath: c) {
        UserDefaults.standard.set(c, forKey: "dshPath")
        return c
    }
    return ""
}

/// 解析 dsh 路径背后的真实脚本文件（跟随符号链接，支持相对链接）
func resolvedScriptPath(_ path: String) -> String {
    var current = path
    for _ in 0..<8 { // 防循环链接
        guard let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: current) else {
            return current
        }
        if resolved.hasPrefix("/") {
            current = resolved
        } else {
            let dir = (current as NSString).deletingLastPathComponent
            current = dir + "/" + resolved
        }
    }
    return current
}

/// 查找 Node.js 可执行文件，用于直接解释 dsh 脚本（避免 GUI 应用环境 PATH 不完整导致 shebang 找不到 node）
func findNodeExecutable() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let staticCandidates: [String] = [
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        home + "/.nvm/versions/node/default/bin/node",
    ]
    for c in staticCandidates where FileManager.default.isExecutableFile(atPath: c) {
        return c
    }
    // 动态扫描 nvm / workbuddy 等版本管理目录
    let versionRoots = [
        home + "/.nvm/versions/node",
        home + "/.workbuddy/binaries/node/versions",
    ]
    for root in versionRoots {
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
        var nodes: [(path: String, date: Date)] = []
        for v in versions {
            let nodePath = root + "/" + v + "/bin/node"
            guard FileManager.default.isExecutableFile(atPath: nodePath) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: nodePath)
            let date = (attrs?[.modificationDate] as? Date) ?? .distantPast
            nodes.append((nodePath, date))
        }
        if let latest = nodes.sorted(by: { $0.date > $1.date }).first {
            return latest.path
        }
    }
    return nil
}

/// 查找与 Node.js 配套的 npm，用于在用户确认后安装官方 DSH 运行时。
func findNpmExecutable() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var candidates = [
        "/opt/homebrew/bin/npm",
        "/usr/local/bin/npm",
        home + "/.nvm/versions/node/default/bin/npm",
    ]
    if let node = findNodeExecutable() {
        candidates.insert((node as NSString).deletingLastPathComponent + "/npm", at: 0)
    }
    candidates += dynamicNodeBinDirs(home: home).map { $0 + "/npm" }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// 把常见 Node 安装目录加入 PATH，确保 dsh 的 shebang `#!/usr/bin/env node` 能找到解释器
func enrichedEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let nodeDirs = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        home + "/.nvm/versions/node/default/bin",
        home + "/.workbuddy/binaries/node/versions/current/bin",
    ] + dynamicNodeBinDirs(home: home)
    let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
    let additions = nodeDirs.filter { FileManager.default.fileExists(atPath: $0) && !existing.contains($0) }
    if !additions.isEmpty {
        env["PATH"] = (additions + existing).joined(separator: ":")
    }
    return env
}

func dynamicNodeBinDirs(home: String) -> [String] {
    var dirs: [String] = []
    for root in [home + "/.nvm/versions/node", home + "/.workbuddy/binaries/node/versions"] {
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
        for v in versions {
            let binDir = root + "/" + v + "/bin"
            if FileManager.default.fileExists(atPath: binDir + "/node") {
                dirs.append(binDir)
            }
        }
    }
    return dirs
}

// MARK: - 状态机

enum DSHState: Equatable {
    case stopped
    case starting
    case running(Int32)
    case externalRunning(Int32)
    case stopping
    case failed(String)

    static func == (l: DSHState, r: DSHState) -> Bool {
        switch (l, r) {
        case (.stopped, .stopped), (.starting, .starting), (.stopping, .stopping):
            return true
        case (.running(let a), .running(let b)):
            return a == b
        case (.externalRunning(let a), .externalRunning(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }

    /// 端口上有服务在监听（无论是本应用启动的还是外部实例）—— 用于「打开浏览器」等
    var portActive: Bool {
        switch self {
        case .running, .externalRunning, .starting:
            return true
        default:
            return false
        }
    }

    /// 空闲状态（stopped / failed）—— 可以尝试启动
    var canTryStart: Bool {
        switch self {
        case .stopped, .failed:
            return true
        default:
            return false
        }
    }

    /// 服务已就绪，可以嵌入显示 DSH 界面
    var webReady: Bool {
        switch self {
        case .running, .externalRunning:
            return true
        default:
            return false
        }
    }
}

enum LocalModelState: Equatable {
    case stopped
    case starting
    case ready
    case stopping
    case failed(String)
}

/// 展开用户输入路径中的 `~`，方便在设置中填写 `~/models/start.sh`。
func expandedUserPath(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}

/// 当前 DSH 用户数据根目录；与从终端设置 `DSH_HOME` 的行为保持一致。
func dshHomeDirectoryURL() -> URL {
    let environmentHome = ProcessInfo.processInfo.environment["DSH_HOME"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if let environmentHome, !environmentHome.isEmpty {
        return URL(fileURLWithPath: expandedUserPath(environmentHome), isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".dsh", isDirectory: true)
}

/// 把常见的命令行参数文本拆成 Process.arguments。
/// 支持单双引号与反斜杠，但不会执行 shell、管道、重定向或命令替换。
func parseCommandArguments(_ input: String) -> [String]? {
    var arguments: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false
    var tokenStarted = false

    for character in input {
        if escaping {
            current.append(character)
            escaping = false
            tokenStarted = true
        } else if character == "\\" && quote != "'" {
            escaping = true
            tokenStarted = true
        } else if let activeQuote = quote {
            if character == activeQuote {
                quote = nil
            } else {
                current.append(character)
            }
            tokenStarted = true
        } else if character == "\"" || character == "'" {
            quote = character
            tokenStarted = true
        } else if character.isWhitespace {
            if tokenStarted {
                arguments.append(current)
                current = ""
                tokenStarted = false
            }
        } else {
            current.append(character)
            tokenStarted = true
        }
    }

    guard quote == nil, !escaping else { return nil }
    if tokenStarted { arguments.append(current) }
    return arguments
}

// MARK: - 归档会话数据

struct ArchivedConversation: Identifiable, Hashable {
    let id: String
    let title: String
    let workspaceTitle: String?
    let cwd: String?
    let createdAt: Date?
    let updatedAt: Date?
    let byteCount: Int64
    let directoryURL: URL?
}

private struct ArchiveWorkspaceInfo {
    let title: String
    let path: String
}

private struct ArchiveSnapshot {
    let items: [ArchivedConversation]
    let totalByteCount: Int64
}

private enum ArchiveManagerError: LocalizedError {
    case message(String)

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
        dataRootURL = dshHomeDirectoryURL()
    }

    var displayDataRoot: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = dataRootURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }
        return path
    }

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

// MARK: - 核心管理器

final class Manager: ObservableObject {
    static let shared = Manager()

    @Published var state: DSHState = .stopped
    @Published var logs: String = ""
    @Published var dshPath: String = UserDefaults.standard.string(forKey: "dshPath") ?? resolveDshPath()
    @Published var host: String = UserDefaults.standard.string(forKey: "host") ?? "127.0.0.1"
    @Published var port: Int = {
        let p = UserDefaults.standard.integer(forKey: "port")
        return p == 0 ? 3080 : p
    }()
    @Published var autoStart: Bool = {
        if let v = UserDefaults.standard.object(forKey: "autoStart") as? Bool { return v }
        return true
    }()
    @Published var stopOnQuit: Bool = {
        if let v = UserDefaults.standard.object(forKey: "stopOnQuit") as? Bool { return v }
        return true
    }()
    @Published var cleanupStaleOnStart: Bool = {
        if let v = UserDefaults.standard.object(forKey: "cleanupStaleOnStart") as? Bool { return v }
        return true
    }()
    @Published var simplifyPluginInventory: Bool = {
        if let value = UserDefaults.standard.object(forKey: "simplifyPluginInventory") as? Bool { return value }
        return true
    }()
    @Published var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @Published var isInstallingRuntime: Bool = false
    @Published var localModelState: LocalModelState = .stopped
    @Published var localModelName: String = UserDefaults.standard.string(forKey: "localModelName") ?? "本地模型"
    @Published var localModelStartExecutable: String = UserDefaults.standard.string(forKey: "localModelStartExecutable") ?? ""
    @Published var localModelStartArguments: String = UserDefaults.standard.string(forKey: "localModelStartArguments") ?? ""
    @Published var localModelStopExecutable: String = UserDefaults.standard.string(forKey: "localModelStopExecutable") ?? ""
    @Published var localModelStopArguments: String = UserDefaults.standard.string(forKey: "localModelStopArguments") ?? ""
    @Published var localModelHealthURL: String = UserDefaults.standard.string(forKey: "localModelHealthURL") ?? ""
    @Published var stopLocalModelOnQuit: Bool = {
        if let value = UserDefaults.standard.object(forKey: "stopLocalModelOnQuit") as? Bool { return value }
        return true
    }()

    private var proc: Process?
    private var installProc: Process?
    private var localModelProc: Process?
    private var localModelStopProc: Process?
    private var localModelStartDeadline: Date?
    private var readyTimer: Timer?
    private var watchTimer: Timer?
    private var logLines: [String] = []
    private var pendingRestart = false
    private var warnedBusy = false
    private var lastHealthCheck: Date?
    private var healthFailStreak = 0

    var url: URL {
        URL(string: "http://\(host):\(port)") ?? URL(string: "http://127.0.0.1:3080")!
    }
    /// 是否由本应用托管了子进程
    var ownsProcess: Bool { proc != nil }
    /// 是否可以点击「启动」
    var canStart: Bool {
        if case .stopped = state { return !dshPath.isEmpty }
        return false
    }
    var localModelDisplayName: String {
        let trimmed = localModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "本地模型" : trimmed
    }
    var localModelStartPath: String { expandedUserPath(localModelStartExecutable) }
    var localModelStopPath: String { expandedUserPath(localModelStopExecutable) }
    var canStartLocalModel: Bool {
        guard FileManager.default.isExecutableFile(atPath: localModelStartPath) else { return false }
        switch localModelState {
        case .stopped, .failed: return true
        case .starting, .ready, .stopping: return false
        }
    }
    var canStopLocalModel: Bool {
        let hasTrackedProcess = localModelProc?.isRunning == true
        let hasStopExecutable = FileManager.default.isExecutableFile(atPath: localModelStopPath)
        guard hasTrackedProcess || hasStopExecutable else { return false }
        switch localModelState {
        case .starting, .ready: return true
        case .stopped, .stopping, .failed: return false
        }
    }
    var canToggleLocalModel: Bool { canStartLocalModel || canStopLocalModel }

    private init() {
        watchTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshExternal()
            self?.refreshLocalModel()
        }
        DispatchQueue.main.async { [weak self] in self?.refreshLocalModel() }
    }

    // MARK: 持久化

    func persist() {
        let d = UserDefaults.standard
        d.set(dshPath, forKey: "dshPath")
        d.set(host, forKey: "host")
        d.set(port, forKey: "port")
        d.set(autoStart, forKey: "autoStart")
        d.set(stopOnQuit, forKey: "stopOnQuit")
        d.set(cleanupStaleOnStart, forKey: "cleanupStaleOnStart")
        d.set(simplifyPluginInventory, forKey: "simplifyPluginInventory")
        d.set(localModelName, forKey: "localModelName")
        d.set(localModelStartExecutable, forKey: "localModelStartExecutable")
        d.set(localModelStartArguments, forKey: "localModelStartArguments")
        d.set(localModelStopExecutable, forKey: "localModelStopExecutable")
        d.set(localModelStopArguments, forKey: "localModelStopArguments")
        d.set(localModelHealthURL, forKey: "localModelHealthURL")
        d.set(stopLocalModelOnQuit, forKey: "stopLocalModelOnQuit")
    }

    // MARK: 本地模型服务

    private var configuredLocalModelHealthURL: URL? {
        let value = localModelHealthURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let url = URL(string: value),
              url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }

    private func isLocalModelHealthy(_ url: URL, timeout: TimeInterval = 2) -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let semaphore = DispatchSemaphore(value: 0)
        var healthy = false
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                healthy = (100...599).contains(http.statusCode)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 1)
        task.cancel()
        return healthy
    }

    func refreshLocalModel() {
        guard localModelState != .stopping else { return }
        guard let healthURL = configuredLocalModelHealthURL else {
            if localModelProc?.isRunning == true {
                localModelState = .ready
            } else if localModelState == .ready {
                localModelState = .stopped
            }
            return
        }

        DispatchQueue.global().async { [weak self] in
            let healthy = self?.isLocalModelHealthy(healthURL) ?? false
            DispatchQueue.main.async {
                guard let self, self.configuredLocalModelHealthURL == healthURL,
                      self.localModelState != .stopping else { return }
                if healthy {
                    self.localModelStartDeadline = nil
                    self.localModelState = .ready
                } else if self.localModelState == .ready, self.localModelProc?.isRunning != true {
                    self.localModelState = .stopped
                } else if self.localModelState == .starting,
                          let deadline = self.localModelStartDeadline,
                          Date() > deadline {
                    self.localModelState = .failed("健康检查超时")
                    self.appendLog("✗ \(self.localModelDisplayName) 未在预期时间内通过健康检查")
                }
            }
        }
    }

    func toggleLocalModel() {
        switch localModelState {
        case .starting, .ready: stopLocalModel()
        case .stopped, .failed: startLocalModel()
        case .stopping: break
        }
    }

    func startLocalModel() {
        persist()
        guard FileManager.default.isExecutableFile(atPath: localModelStartPath) else {
            localModelState = .failed("启动程序不存在或不可执行")
            appendLog("✗ 本地模型启动程序无效：\(localModelStartPath)")
            return
        }
        guard let arguments = parseCommandArguments(localModelStartArguments) else {
            localModelState = .failed("启动参数中的引号或转义不完整")
            return
        }
        guard canStartLocalModel else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: localModelStartPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: localModelStartPath).deletingLastPathComponent()
        process.environment = enrichedEnvironment()
        attachLocalModelOutput(to: process)
        process.terminationHandler = { [weak self, weak process] finished in
            let exitCode = finished.terminationStatus
            DispatchQueue.main.async {
                guard let self, let process, self.localModelProc === process else { return }
                self.localModelProc = nil
                if self.localModelState == .stopping {
                    self.localModelState = .stopped
                } else if exitCode != 0 {
                    self.localModelStartDeadline = nil
                    self.localModelState = .failed("启动程序退出码 \(exitCode)")
                    self.appendLog("✗ \(self.localModelDisplayName) 启动程序异常退出（\(exitCode)）")
                } else if self.configuredLocalModelHealthURL != nil {
                    self.refreshLocalModel()
                } else {
                    self.localModelState = .stopped
                    self.appendLog("ℹ️ \(self.localModelDisplayName) 启动程序已结束")
                }
            }
        }

        do {
            localModelState = .starting
            localModelStartDeadline = configuredLocalModelHealthURL == nil ? nil : Date().addingTimeInterval(120)
            try process.run()
            localModelProc = process
            appendLog("🧠 正在启动 \(localModelDisplayName)…")
            if configuredLocalModelHealthURL == nil { localModelState = .ready }
        } catch {
            localModelStartDeadline = nil
            localModelState = .failed(error.localizedDescription)
            appendLog("✗ 无法启动 \(localModelDisplayName)：\(error.localizedDescription)")
        }
    }

    func stopLocalModel() {
        guard canStopLocalModel else { return }
        localModelState = .stopping
        localModelStartDeadline = nil

        if let process = localModelProc {
            localModelProc = nil
            process.terminationHandler = nil
            process.terminate()
        }

        guard FileManager.default.isExecutableFile(atPath: localModelStopPath) else {
            localModelState = .stopped
            appendLog("⏹ 已停止 \(localModelDisplayName)")
            return
        }
        guard let arguments = parseCommandArguments(localModelStopArguments) else {
            localModelState = .failed("停止参数中的引号或转义不完整")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: localModelStopPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: localModelStopPath).deletingLastPathComponent()
        process.environment = enrichedEnvironment()
        attachLocalModelOutput(to: process)
        process.terminationHandler = { [weak self, weak process] finished in
            let exitCode = finished.terminationStatus
            DispatchQueue.main.async {
                guard let self, let process, self.localModelStopProc === process else { return }
                self.localModelStopProc = nil
                if exitCode == 0 {
                    self.localModelState = .stopped
                    self.appendLog("⏹ 已停止 \(self.localModelDisplayName)")
                } else {
                    self.localModelState = .failed("停止程序退出码 \(exitCode)")
                    self.appendLog("✗ \(self.localModelDisplayName) 停止程序异常退出（\(exitCode)）")
                }
            }
        }

        do {
            try process.run()
            localModelStopProc = process
            appendLog("⏹ 正在停止 \(localModelDisplayName)…")
        } catch {
            localModelState = .failed(error.localizedDescription)
            appendLog("✗ 无法停止 \(localModelDisplayName)：\(error.localizedDescription)")
        }
    }

    private func attachLocalModelOutput(to process: Process) {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let output = String(data: data, encoding: .utf8) else { return }
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.appendLog("\(self.localModelDisplayName) · \(text)")
            }
        }
    }

    // MARK: 日志

    func appendLog(_ s: String) {
        logLines.append(s)
        if logLines.count > 4000 { logLines.removeFirst(logLines.count - 4000) }
        logs = logLines.joined(separator: "\n")
    }

    func clearLogs() {
        logLines.removeAll()
        logs = ""
    }

    // MARK: 安装官方 DSH 运行时

    /// 用户主动点击后，通过 npm 安装官方 @deepseek-ai/dsh 到稳定的用户目录。
    /// 使用 Process 参数数组而不是 shell 字符串，避免命令注入和 PATH 差异。
    func installOfficialRuntime() {
        guard !isInstallingRuntime else { return }
        guard let npm = findNpmExecutable() else {
            state = .failed("未找到 npm，请先安装 Node.js 22.19+ 或 24+")
            appendLog("✗ 未找到 npm；请先从 https://nodejs.org/ 安装 Node.js")
            return
        }

        let prefix = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh/app", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        } catch {
            state = .failed("无法创建 DSH 安装目录: \(error.localizedDescription)")
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: npm)
        p.arguments = [
            "install",
            "--prefix", prefix.path,
            "@deepseek-ai/dsh@latest",
            "--no-fund",
            "--no-audit",
        ]
        p.currentDirectoryURL = prefix
        p.environment = enrichedEnvironment()

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.finishRuntimeInstall(exitCode: process.terminationStatus, prefix: prefix)
            }
        }

        let fh = pipe.fileHandleForReading
        fh.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let output = String(data: data, encoding: .utf8) else { return }
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            DispatchQueue.main.async { self?.appendLog(text) }
        }

        do {
            try p.run()
            installProc = p
            isInstallingRuntime = true
            state = .stopped
            appendLog("⬇️ 正在安装官方 @deepseek-ai/dsh → \(prefix.path)")
        } catch {
            state = .failed("启动 npm 失败: \(error.localizedDescription)")
            appendLog("✗ 启动 npm 失败: \(error.localizedDescription)")
        }
    }

    private func finishRuntimeInstall(exitCode: Int32, prefix: URL) {
        installProc = nil
        isInstallingRuntime = false
        let installed = prefix.appendingPathComponent("node_modules/.bin/dsh").path
        guard exitCode == 0, FileManager.default.isExecutableFile(atPath: installed) else {
            state = .failed("DSH 安装失败（npm 退出码 \(exitCode)），请在设置中查看日志")
            appendLog("✗ 官方 DSH 运行时安装失败（npm 退出码 \(exitCode)）")
            return
        }

        dshPath = installed
        persist()
        state = .stopped
        appendLog("✅ 官方 DSH 运行时安装完成")
        start()
    }

    // MARK: 自动启动 / 外部实例检测

    /// 打开应用时调用：检测外部实例，或按设置自动启动服务
    /// 关键修复：接管外部实例前先做真实 HTTP 健康检查——只接管「活着的」dsh；
    /// 端口被「假活」的残留进程占用时，默认自动清理后重新启动（可在设置中关闭）。
    func startIfNeeded() {
        guard let pid = listeningPid(port: port) else {
            guard autoStart else { return }
            guard case .stopped = state else { return }
            start()
            return
        }
        guard commandOf(pid: pid).contains("dsh") else {
            appendLog("⚠️ 端口 \(port) 被其他进程 (pid \(pid)) 占用，无法启动")
            return
        }
        // 端口上是 dsh 进程：后台做 HTTP 健康检查，再决定 接管 / 清理 / 启动
        let hostHere = host
        let portHere = port
        appendLog("🔍 端口 \(portHere) 上有 dsh 进程 (pid \(pid))，正在做健康检查…")
        DispatchQueue.global().async { [weak self] in
            let healthy = isHttpAlive(hostHere, portHere)
            DispatchQueue.main.async {
                self?.finishStartIfNeeded(healthy: healthy, port: portHere)
            }
        }
    }

    /// startIfNeeded 的健康检查结果处理（主线程）
    private func finishStartIfNeeded(healthy: Bool, port: Int) {
        // 健康检查期间端口状态可能已变化，重新确认
        guard let nowPid = listeningPid(port: port) else {
            start()
            return
        }
        if healthy {
            state = .externalRunning(nowPid)
            appendLog("ℹ️ 检测到已在运行的健康 dsh 实例 (pid \(nowPid))，直接使用")
        } else {
            appendLog("⚠️ 端口 \(port) 被无响应的 dsh 进程 (pid \(nowPid)) 占用")
            if cleanupStaleOnStart {
                if forceFreePort(pid: nowPid, port: port, label: "清理残留 dsh 进程") {
                    appendLog("🔄 残留进程已清理，继续启动…")
                    start()
                } else {
                    state = .failed("端口 \(port) 上的残留 dsh 进程无法清理")
                }
            } else {
                state = .failed("端口 \(port) 被无响应的 dsh 进程 (pid \(nowPid)) 占用；可在设置中开启「自动清理」")
            }
        }
    }

    func refreshExternal() {
        guard proc == nil else { return }
        let pid = listeningPid(port: port)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.handleExternalPoll(pid: pid)
        }
    }

    /// 端口轮询：发现/未发现 dsh 进程时的处理（主线程）
    private func handleExternalPoll(pid: Int32?) {
        let portHere = port
        let hostHere = host
        guard let pid = pid else {
            warnedBusy = false
            if case .externalRunning = state {
                state = .stopped
                appendLog("外部实例已退出")
            }
            return
        }
        let cmd = commandOf(pid: pid)
        guard cmd.contains("dsh") else {
            if !warnedBusy && state.canTryStart {
                warnedBusy = true
                appendLog("⚠️ 端口 \(portHere) 被其他进程 (pid \(pid)) 占用，无法启动")
            }
            return
        }
        // 12 秒内已对同一实例做过健康检查 → 跳过，避免频繁发起请求
        if case .externalRunning(let cur) = state, cur == pid,
           let last = lastHealthCheck, Date().timeIntervalSince(last) < 12 {
            return
        }
        lastHealthCheck = Date()
        // 真实 HTTP 健康检查放后台线程，结果回到主线程处理
        DispatchQueue.global().async { [weak self] in
            let healthy = isHttpAlive(hostHere, portHere)
            DispatchQueue.main.async {
                self?.applyExternalHealth(pid: pid, healthy: healthy, port: portHere)
            }
        }
    }

    /// 根据健康检查结果决定 接管 / 自动清理 / 报错（主线程）
    private func applyExternalHealth(pid: Int32, healthy: Bool, port: Int) {
        if healthy {
            healthFailStreak = 0
            if case .externalRunning(let cur) = state, cur == pid { return }
            state = .externalRunning(pid)
            appendLog("ℹ️ 检测到已在运行的健康 dsh 实例 (pid \(pid))，直接使用")
        } else {
            healthFailStreak += 1
            // 连续两次无响应才判定为残留，避免瞬时抖动误杀
            if healthFailStreak >= 2 {
                healthFailStreak = 0
                appendLog("⚠️ 端口 \(port) 上的 dsh 进程 (pid \(pid)) 无响应")
                if cleanupStaleOnStart {
                    state = .stopped
                    killProcess(pid: pid, label: "自动清理无响应的残留 dsh 进程")
                } else if case .externalRunning = state {
                    state = .failed("端口 \(port) 被无响应的 dsh 进程 (pid \(pid)) 占用")
                }
            }
        }
    }

    // MARK: 启动

    func start() {
        persist()
        guard !dshPath.isEmpty else {
            state = .failed("未找到 dsh 命令，请在设置中手动指定路径")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: dshPath) else {
            state = .failed("dsh 路径无效: \(dshPath)")
            return
        }
        guard case .stopped = state else { return }

        if let busy = listeningPid(port: port) {
            let isDsh = commandOf(pid: busy).contains("dsh")
            if isDsh && isHttpAlive(host, port) {
                // 端口上已有健康的 dsh 实例，直接接管而不是重复启动
                state = .externalRunning(busy)
                appendLog("ℹ️ 端口 \(port) 上已有健康的 dsh 实例 (pid \(busy))，直接使用")
                return
            }
            if isDsh && cleanupStaleOnStart {
                appendLog("⚠️ 端口 \(port) 被无响应的 dsh 进程 (pid \(busy)) 占用，自动清理后重新启动")
                if forceFreePort(pid: busy, port: port, label: "清理残留 dsh 进程") {
                    // 端口已释放，继续往下启动
                } else {
                    state = .failed("端口 \(port) 上的残留 dsh 进程无法清理")
                    return
                }
            } else {
                appendLog("⚠️ 端口 \(port) 已被进程 \(busy) 占用，无法启动")
                refreshExternal()
                return
            }
        }

        let p = Process()
        // 优先用显式 node 解释器直接运行 dsh 的 bin.js：
        // GUI 应用从 Finder/LaunchServices 启动时 PATH 往往不含任何 node，
        // 依赖 shebang `#!/usr/bin/env node` 会直接失败。
        // 显式 node + 脚本路径的方式对环境 PATH 零依赖，最稳。
        let script = resolvedScriptPath(dshPath)
        if let node = findNodeExecutable(), script.hasSuffix(".js") {
            p.executableURL = URL(fileURLWithPath: node)
            p.arguments = [script, "web", "--host", host, "--port", "\(port)", "--no-open"]
        } else {
            p.executableURL = URL(fileURLWithPath: dshPath)
            p.arguments = ["web", "--host", host, "--port", "\(port)", "--no-open"]
        }
        p.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        // 双保险：同时补充 PATH，覆盖直接执行分支及 dsh 内部再拉起子进程的场景
        p.environment = enrichedEnvironment()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.handleExit() }
        }

        do {
            try p.run()
        } catch {
            state = .failed("启动失败: \(error.localizedDescription)")
            appendLog("✗ 启动失败: \(error.localizedDescription)")
            return
        }

        proc = p
        state = .starting
        appendLog("▶ 启动 dsh web → \(url.absoluteString)  (pid \(p.processIdentifier))")

        let fh = pipe.fileHandleForReading
        fh.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let s = String(data: data, encoding: .utf8) else { return }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            DispatchQueue.main.async { self?.appendLog(trimmed) }
        }

        waitForReady()
    }

    private func waitForReady() {
        readyTimer?.invalidate()
        var tries = 0
        let hostHere = host
        let portHere = port
        readyTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            // HTTP 健康检查放后台线程，避免阻塞主线程
            DispatchQueue.global().async {
                let healthy = isHttpAlive(hostHere, portHere)
                DispatchQueue.main.async {
                    // self 已在外部闭包解包为强引用，直接使用（不再重复 guard）
                    guard self.proc != nil, self.state == .starting else { t.invalidate(); return }
                    if healthy {
                        t.invalidate()
                        self.readyTimer = nil
                        if let pid = self.proc?.processIdentifier {
                            self.state = .running(pid)
                            self.appendLog("✅ dsh web 就绪 → \(self.url.absoluteString)")
                        }
                    } else {
                        tries += 1
                        if tries > 120 { // 60 秒仍未就绪：明确报错，而不是永远停在「启动中」
                            t.invalidate()
                            self.readyTimer = nil
                            self.state = .failed("启动超时：端口 \(portHere) 60 秒内无 HTTP 响应")
                            self.appendLog("✗ 启动超时：\(self.url.absoluteString) 60 秒内无 HTTP 响应")
                        }
                    }
                }
            }
        }
    }

    private func isPortOpen(_ host: String, _ port: Int) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>? = nil
        let name = host.isEmpty ? "127.0.0.1" : host
        guard getaddrinfo(name, "\(port)", &hints, &res) == 0, let r = res else { return false }
        defer { freeaddrinfo(r) }
        var ptr: UnsafeMutablePointer<addrinfo>? = r
        while let cur = ptr {
            let fd = socket(cur.pointee.ai_family, cur.pointee.ai_socktype, cur.pointee.ai_protocol)
            if fd >= 0 {
                var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                if connect(fd, cur.pointee.ai_addr, cur.pointee.ai_addrlen) == 0 {
                    close(fd)
                    return true
                }
                close(fd)
            }
            ptr = cur.pointee.ai_next
        }
        return false
    }

    // MARK: 停止 / 重启

    func stop() {
        guard let p = proc else { return }
        state = .stopping
        appendLog("⏹ 正在停止 (pid \(p.processIdentifier)) …")
        p.terminate()
        let pid = p.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
                DispatchQueue.main.async {
                    self?.appendLog("进程未响应，已强制结束 (pid \(pid))")
                }
            }
        }
    }

    func restart() {
        guard proc != nil else {
            start()
            return
        }
        pendingRestart = true
        stop()
    }

    func killExternal() {
        guard case .externalRunning(let pid) = state else { return }
        state = .stopped
        killProcess(pid: pid, label: "停止外部 dsh 实例")
    }

    /// 终止进程：先 SIGTERM，4 秒后仍存活则 SIGKILL；结束后刷新端口状态
    func killProcess(pid: Int32, label: String) {
        appendLog("⏹ \(label) (pid \(pid)) …")
        if kill(pid, SIGTERM) != 0 {
            appendLog("无法向 pid \(pid) 发送信号: \(String(cString: strerror(errno)))")
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) { [weak self] in
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
            DispatchQueue.main.async { self?.refreshExternal() }
        }
    }

    /// 同步清理占用端口的进程并等待端口释放（启动/接管前调用）；返回端口是否已空闲。
    /// 只用于「残留的无响应 dsh 进程」，阻塞主线程数秒换取确定性。
    @discardableResult
    func forceFreePort(pid: Int32, port: Int, label: String) -> Bool {
        appendLog("⏹ \(label) (pid \(pid)) …")
        if kill(pid, SIGTERM) != 0 {
            appendLog("无法向 pid \(pid) 发送信号: \(String(cString: strerror(errno)))")
            return false
        }
        for _ in 0..<6 { // 最多等 3 秒优雅退出
            usleep(500_000)
            if listeningPid(port: port) == nil { return true }
        }
        if kill(pid, SIGKILL) == 0 {
            appendLog("进程未在 3 秒内退出，已强制结束 (pid \(pid))")
        }
        for _ in 0..<4 { // 再等最多 2 秒
            usleep(500_000)
            if listeningPid(port: port) == nil { return true }
        }
        appendLog("⚠️ 端口 \(port) 仍被占用，清理未完全生效")
        return false
    }

    private func handleExit() {
        proc = nil
        readyTimer?.invalidate()
        readyTimer = nil
        appendLog("⏹ dsh web 已退出")
        if pendingRestart {
            pendingRestart = false
            state = .stopped
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.start()
            }
        } else {
            state = .stopped
            refreshExternal()
        }
    }

    /// 退出应用时清理子进程（受「退出时停止服务」开关控制）
    func terminateChild() {
        installProc?.terminate()
        localModelStopProc?.terminate()
        if stopLocalModelOnQuit {
            localModelProc?.terminate()
            if FileManager.default.isExecutableFile(atPath: localModelStopPath),
               let arguments = parseCommandArguments(localModelStopArguments) {
                let stopProcess = Process()
                stopProcess.executableURL = URL(fileURLWithPath: localModelStopPath)
                stopProcess.arguments = arguments
                stopProcess.currentDirectoryURL = URL(fileURLWithPath: localModelStopPath).deletingLastPathComponent()
                stopProcess.environment = enrichedEnvironment()
                stopProcess.standardOutput = FileHandle.nullDevice
                stopProcess.standardError = FileHandle.nullDevice
                try? stopProcess.run()
            }
        }
        guard stopOnQuit else { return }
        if let p = proc {
            p.terminate()
        }
    }

    // MARK: 开机自启

    func toggleLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        } catch {
            appendLog("⚠️ 设置开机自启失败: \(error.localizedDescription)（请把应用放入 /Applications 后重试）")
        }
    }
}

// MARK: - 应用委托（退出时清理）

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        Manager.shared.terminateChild()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - 内嵌 DSH 界面

/// `dsh plugin --profile web add ...` 会把用户安装的 Bundle 记录在这个 profile 的 dependencies 中。
/// 官方 Base/Web Bundle 由 DSH 运行时提供，不会出现在这里，因此可作为稳定的“用户安装”边界。
func webProfileUserPluginPackages() -> [String] {
    let packageURL = dshHomeDirectoryURL()
        .appendingPathComponent("profiles/web/package.json")
    guard let data = try? Data(contentsOf: packageURL),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let dependencies = root["dependencies"] as? [String: Any] else { return [] }
    return dependencies.keys.sorted()
}

private func javascriptJSON(_ value: Any, fallback: String) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let result = String(data: data, encoding: .utf8) else { return fallback }
    return result
}

/// 在客户端内嵌 Web UI 中把底层 Loader inventory 重排为用户视图。
/// 只依赖上游明确输出的 data-plugin-entry/data-phase/data-enabled 属性；结构不匹配时不做任何修改。
func pluginInventoryEnhancementScript(enabled: Bool, userPackages: [String]) -> String {
    let enabledLiteral = enabled ? "true" : "false"
    let packagesLiteral = javascriptJSON(userPackages, fallback: "[]")
    return #"""
    (() => {
      const globalKey = "__dshDesktopPluginInventory";
      const initialEnabled = \#(enabledLiteral);
      const initialPackages = \#(packagesLiteral);
      const existing = window[globalKey];
      if (existing && typeof existing.configure === "function") {
        existing.configure(initialEnabled, initialPackages);
        return;
      }

      const storageKey = "dshDesktop.pluginInventory.mode";
      let storedMode = "user";
      try { storedMode = localStorage.getItem(storageKey) || "user"; } catch (_) {}
      if (!["user", "issues", "all"].includes(storedMode)) storedMode = "user";

      const state = {
        enabled: initialEnabled,
        packages: new Set(initialPackages),
        mode: storedMode,
      };
      let scheduled = false;

      function copy() {
        const language = (document.documentElement.lang || navigator.language || "").toLowerCase();
        const zh = language.startsWith("zh");
        return zh ? {
          user: "用户安装",
          issues: "异常 / 等待",
          all: "全部运行单元",
          headingUser: "用户安装的插件",
          headingIssues: "需要关注的运行单元",
          headingAll: "全部运行单元（高级诊断）",
          emptyUser: "没有识别到用户安装插件贡献的运行单元。",
          emptyIssues: "当前没有挂载失败、等待依赖或加载中的运行单元。",
          note: (packages, units, hidden) => `${packages} 个用户包贡献 ${units} 个运行单元；默认隐藏 ${hidden} 个官方/内部运行单元。`,
        } : {
          user: "User installed",
          issues: "Issues / waiting",
          all: "All runtime units",
          headingUser: "User-installed plugins",
          headingIssues: "Runtime units needing attention",
          headingAll: "All runtime units (advanced diagnostics)",
          emptyUser: "No runtime units from user-installed plugins were identified.",
          emptyIssues: "No runtime units are failed, waiting for dependencies, or loading.",
          note: (packages, units, hidden) => `${packages} user packages contribute ${units} runtime units; ${hidden} official/internal units are hidden by default.`,
        };
      }

      function isUserModule(moduleName) {
        for (const packageName of state.packages) {
          if (moduleName === packageName || moduleName.startsWith(`${packageName}/`)) return true;
        }
        return false;
      }

      function facts(card) {
        const title = card.querySelector("strong[title]");
        const moduleName = title ? (title.getAttribute("title") || "") : "";
        const phaseNode = card.querySelector("[data-phase]");
        const phase = phaseNode ? phaseNode.getAttribute("data-phase") : "unobserved";
        const enabledNode = card.querySelector("[data-enabled]");
        const configured = enabledNode && enabledNode.getAttribute("data-enabled") === "true";
        const issue = configured && ["failed", "pending", "loading", "unloading", "unobserved"].includes(phase || "unobserved");
        return { card, moduleName, user: isUserModule(moduleName), issue };
      }

      function setText(node, value) {
        if (node && node.textContent !== String(value)) node.textContent = String(value);
      }

      function makeControls(catalog, list) {
        let controls = Array.from(catalog.children).find((node) => node.hasAttribute && node.hasAttribute("data-dsh-desktop-inventory-controls"));
        if (controls) return controls;

        controls = document.createElement("div");
        controls.setAttribute("data-dsh-desktop-inventory-controls", "true");
        const choices = document.createElement("div");
        choices.setAttribute("data-dsh-desktop-inventory-choices", "true");
        for (const mode of ["user", "issues", "all"]) {
          const button = document.createElement("button");
          button.type = "button";
          button.setAttribute("data-dsh-desktop-mode", mode);
          const label = document.createElement("span");
          label.setAttribute("data-dsh-desktop-label", "true");
          const count = document.createElement("span");
          count.setAttribute("data-dsh-desktop-count", "true");
          button.append(label, count);
          button.addEventListener("click", () => {
            state.mode = mode;
            try { localStorage.setItem(storageKey, mode); } catch (_) {}
            schedule();
          });
          choices.appendChild(button);
        }
        const note = document.createElement("p");
        note.setAttribute("data-dsh-desktop-inventory-note", "true");
        const empty = document.createElement("p");
        empty.setAttribute("data-dsh-desktop-inventory-empty", "true");
        empty.hidden = true;
        controls.append(choices, note, empty);

        const heading = catalog.querySelector("[data-plugin-count]")?.parentElement;
        catalog.insertBefore(controls, heading || list);
        return controls;
      }

      function restoreUpstream(catalog, list) {
        for (const card of Array.from(list.children)) {
          if (card.matches && card.matches("li[data-plugin-entry]")) card.hidden = false;
        }
        const controls = Array.from(catalog.children).find((node) => node.hasAttribute && node.hasAttribute("data-dsh-desktop-inventory-controls"));
        if (controls) controls.hidden = true;
        const count = catalog.querySelector("[data-plugin-count]");
        const heading = count ? count.parentElement?.querySelector("h3") : null;
        if (heading && heading.dataset.dshDesktopOriginalHeading) setText(heading, heading.dataset.dshDesktopOriginalHeading);
        const cards = Array.from(list.children).filter((node) => node.matches && node.matches("li[data-plugin-entry]"));
        setText(count, cards.length);
      }

      function applyList(list) {
        const catalog = list.parentElement;
        if (!catalog) return;
        if (!state.enabled) {
          restoreUpstream(catalog, list);
          return;
        }

        const labels = copy();
        const rows = Array.from(list.children)
          .filter((node) => node.matches && node.matches("li[data-plugin-entry]"))
          .map(facts);
        const userCount = rows.filter((row) => row.user).length;
        const issueCount = rows.filter((row) => row.issue).length;
        const internalCount = rows.filter((row) => !row.user).length;
        let visibleCount = 0;
        for (const row of rows) {
          const visible = state.mode === "all" || (state.mode === "user" ? row.user : row.issue);
          row.card.hidden = !visible;
          if (visible) visibleCount += 1;
        }

        const controls = makeControls(catalog, list);
        controls.hidden = false;
        for (const button of controls.querySelectorAll("button[data-dsh-desktop-mode]")) {
          const mode = button.getAttribute("data-dsh-desktop-mode");
          button.setAttribute("aria-pressed", mode === state.mode ? "true" : "false");
          const label = button.querySelector("[data-dsh-desktop-label]");
          const count = button.querySelector("[data-dsh-desktop-count]");
          setText(label, labels[mode]);
          setText(count, mode === "user" ? userCount : (mode === "issues" ? issueCount : rows.length));
        }
        setText(
          controls.querySelector("[data-dsh-desktop-inventory-note]"),
          labels.note(state.packages.size, userCount, internalCount)
        );
        const empty = controls.querySelector("[data-dsh-desktop-inventory-empty]");
        if (empty) {
          empty.hidden = visibleCount !== 0;
          setText(empty, state.mode === "issues" ? labels.emptyIssues : labels.emptyUser);
        }

        const count = catalog.querySelector("[data-plugin-count]");
        const heading = count ? count.parentElement?.querySelector("h3") : null;
        if (heading && !heading.dataset.dshDesktopOriginalHeading) heading.dataset.dshDesktopOriginalHeading = heading.textContent || "";
        setText(heading, state.mode === "user" ? labels.headingUser : (state.mode === "issues" ? labels.headingIssues : labels.headingAll));
        setText(count, visibleCount);
      }

      function apply() {
        scheduled = false;
        const lists = new Set();
        for (const card of document.querySelectorAll("li[data-plugin-entry]")) {
          if (card.parentElement) lists.add(card.parentElement);
        }
        for (const list of lists) applyList(list);
      }

      function schedule() {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(apply);
      }

      const style = document.createElement("style");
      style.setAttribute("data-dsh-desktop-plugin-inventory", "true");
      style.textContent = `
        [data-dsh-desktop-inventory-controls] { display:flex; flex-direction:column; gap:8px; padding:10px; border:1px solid var(--dsw-alias-border-l2); border-radius:10px; background:var(--dsw-alias-bg-layer-1); }
        [data-dsh-desktop-inventory-controls][hidden], li[data-plugin-entry][hidden], [data-dsh-desktop-inventory-empty][hidden] { display:none !important; }
        [data-dsh-desktop-inventory-choices] { display:flex; flex-wrap:wrap; gap:7px; }
        [data-dsh-desktop-inventory-choices] button { border:1px solid var(--dsw-alias-border-l2); color:var(--dsw-alias-label-secondary); background:var(--dsw-alias-bg-layer-3); min-height:30px; border-radius:7px; padding:4px 10px; font:inherit; font-size:12px; cursor:pointer; display:inline-flex; align-items:center; gap:6px; }
        [data-dsh-desktop-inventory-choices] button:hover { background:var(--dsw-alias-interactive-bg-hover); }
        [data-dsh-desktop-inventory-choices] button[aria-pressed=true] { border-color:var(--dsw-alias-state-business-primary); color:var(--dsw-alias-state-business-primary); background:color-mix(in srgb, var(--dsw-alias-state-business-primary) 10%, transparent); }
        [data-dsh-desktop-count] { min-width:18px; padding:0 5px; border-radius:999px; text-align:center; font-variant-numeric:tabular-nums; background:var(--dsw-alias-bg-module-platform); }
        [data-dsh-desktop-inventory-note], [data-dsh-desktop-inventory-empty] { margin:0; color:var(--dsw-alias-label-tertiary); font-size:12px; line-height:18px; }
        [data-dsh-desktop-inventory-empty] { padding:10px 2px 2px; }
      `;
      document.head.appendChild(style);

      const observer = new MutationObserver(schedule);
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["data-phase", "data-enabled", "title"],
      });

      window[globalKey] = {
        configure(nextEnabled, nextPackages) {
          state.enabled = Boolean(nextEnabled);
          state.packages = new Set(Array.isArray(nextPackages) ? nextPackages : []);
          schedule();
        },
        refresh: schedule,
      };
      schedule();
    })();
    """#
}

private func pluginInventoryPreferenceScript(enabled: Bool, userPackages: [String]) -> String {
    let enabledLiteral = enabled ? "true" : "false"
    let packagesLiteral = javascriptJSON(userPackages, fallback: "[]")
    return "window.__dshDesktopPluginInventory?.configure(\(enabledLiteral), \(packagesLiteral));"
}

struct WebView: NSViewRepresentable {
    let url: URL
    let simplifyPluginInventory: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let packages = webProfileUserPluginPackages()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(
            source: pluginInventoryEnhancementScript(
                enabled: simplifyPluginInventory,
                userPackages: packages
            ),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        context.coordinator.lastURL = url
        context.coordinator.simplifyPluginInventory = simplifyPluginInventory
        context.coordinator.userPluginPackages = packages
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let packages = webProfileUserPluginPackages()
        context.coordinator.simplifyPluginInventory = simplifyPluginInventory
        context.coordinator.userPluginPackages = packages
        context.coordinator.applyPluginInventoryPreferences(to: nsView)
        guard context.coordinator.lastURL != url else { return }
        context.coordinator.lastURL = url
        nsView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastURL: URL?
        var simplifyPluginInventory = true
        var userPluginPackages: [String] = []

        func applyPluginInventoryPreferences(to webView: WKWebView) {
            webView.evaluateJavaScript(pluginInventoryPreferenceScript(
                enabled: simplifyPluginInventory,
                userPackages: userPluginPackages
            ))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyPluginInventoryPreferences(to: webView)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil, let u = navigationAction.request.url {
                // 新窗口链接交给系统浏览器
                NSWorkspace.shared.open(u)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

// MARK: - 主界面

struct ContentView: View {
    // 全局共享的一个manager实例，dsh状态、日志、端口、dsh路径、启动停止方法
    @ObservedObject private var mgr = Manager.shared // boserveobject是告诉界面观察这个对象，属性变化需要重新计算界面
    @State private var showSettings = false // 是否显示设置
    @State private var showArchiveManager = false // 是否显示归档管理
    @State private var confirmKillExternal = false // 是否显示停止确认框

    var body: some View {
        VStack(spacing: 0) { // 垂直排列
            toolbar // 工具栏
            Divider() // 分割线
            ZStack { // 主要内容，zstack 重叠容器
                if mgr.state.webReady { // if else 只显示一个界面，检查mgr状态，可访问/不可访问
                    WebView(
                        url: mgr.url,
                        simplifyPluginInventory: mgr.simplifyPluginInventory
                    )
                } else {
                    placeholderView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 620)
        .onAppear { mgr.startIfNeeded() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showArchiveManager) {
            ArchiveManagerView()
        }
        .alert("停止外部实例", isPresented: $confirmKillExternal) {
            Button("停止", role: .destructive) { mgr.killExternal() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将向外部 dsh 进程发送终止信号。该进程不是由本应用启动的，确定要停止它吗？")
        }
    }

    // MARK: 工具栏

    private var toolbar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText).font(.system(.body, weight: .medium))
            Text(mgr.url.absoluteString)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: { mgr.start() }) {
                Label("启动", systemImage: "play.fill")
            }
            .disabled(!mgr.canStart)

            Button(action: { mgr.stop() }) {
                Label("停止", systemImage: "stop.fill")
            }
            .disabled(!mgr.ownsProcess)

            Button(action: { mgr.restart() }) {
                Label("重启", systemImage: "arrow.clockwise")
            }
            .disabled(!mgr.ownsProcess)

            Divider().frame(height: 18)

            Button(action: { mgr.toggleLocalModel() }) {
                Label(localModelButtonText, systemImage: localModelSystemImage)
            }
            .disabled(!mgr.canToggleLocalModel)
            .help(localModelHelpText)

            Button(action: { NSWorkspace.shared.open(mgr.url) }) {
                Label("系统浏览器", systemImage: "safari")
            }
            .disabled(!mgr.state.portActive)

            if case .externalRunning(let pid) = mgr.state {
                Button(action: { confirmKillExternal = true }) {
                    Label("接管并停止", systemImage: "xmark.circle")
                }
                .help("停止由其他方式启动的 dsh (pid \(pid))")
            }

            Divider().frame(height: 18)

            Button(action: { showArchiveManager = true }) {
                Label("归档管理", systemImage: "archivebox")
                    .labelStyle(.iconOnly)
            }
            .help("查看、恢复或清理已归档会话")

            Button(action: { showSettings = true }) {
                Label("设置", systemImage: "gearshape")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statusText: String {
        if mgr.isInstallingRuntime { return "正在安装 DSH…" }
        switch mgr.state {
        case .stopped: return "已停止"
        case .starting: return "启动中…"
        case .running(let pid): return "运行中 (pid \(pid))"
        case .externalRunning(let pid): return "运行中 · 外部实例 (pid \(pid))"
        case .stopping: return "停止中…"
        case .failed(let msg): return "异常：\(msg)"
        }
    }

    private var statusColor: Color {
        if mgr.isInstallingRuntime { return .orange }
        switch mgr.state {
        case .stopped: return .gray
        case .starting, .stopping: return .orange
        case .running, .externalRunning: return .green
        case .failed: return .red
        }
    }

    private var localModelButtonText: String {
        switch mgr.localModelState {
        case .stopped, .failed: return "启动模型"
        case .starting, .ready: return "停止模型"
        case .stopping: return "停止中…"
        }
    }

    private var localModelSystemImage: String {
        switch mgr.localModelState {
        case .stopped: return "cpu"
        case .starting: return "hourglass"
        case .ready: return "stop.circle.fill"
        case .stopping: return "hourglass"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var localModelHelpText: String {
        if mgr.localModelStartExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先在设置中配置本地模型启动程序"
        }
        switch mgr.localModelState {
        case .stopped: return "启动 \(mgr.localModelDisplayName)"
        case .starting: return mgr.canStopLocalModel ? "模型正在启动；点击停止" : "模型正在启动"
        case .ready:
            return mgr.canStopLocalModel
                ? "\(mgr.localModelDisplayName) 已就绪；点击停止"
                : "模型已就绪；配置停止程序后可从此处停止"
        case .stopping: return "正在停止 \(mgr.localModelDisplayName)"
        case .failed(let message): return "本地模型异常：\(message)"
        }
    }

    // MARK: 未运行时的占位页

    private var placeholderView: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("DSH 服务未运行").font(.title3).bold()
            Text(mgr.url.absoluteString)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
            if mgr.isInstallingRuntime {
                ProgressView().controlSize(.small)
                Text("正在通过 npm 安装官方 @deepseek-ai/dsh…")
                    .foregroundColor(.secondary)
                Text("安装完成后将自动启动服务")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if mgr.dshPath.isEmpty {
                if case .failed(let msg) = mgr.state {
                    Text(msg).foregroundColor(.red).font(.callout)
                } else {
                    Text("未找到 DeepSeek Harness 运行时")
                        .foregroundColor(.secondary)
                        .font(.callout)
                }
                Button(action: { mgr.installOfficialRuntime() }) {
                    Label("一键安装官方 DSH 运行时", systemImage: "arrow.down.circle.fill")
                }
                .controlSize(.large)
                Text("需要 Node.js 22.19+ 或 24+；运行时将安装到 ~/.dsh/app")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if mgr.state == .stopped {
                Button(action: { mgr.start() }) {
                    Label("启动服务", systemImage: "play.fill")
                }
                .controlSize(.large)
                .disabled(!mgr.canStart)
            } else if case .failed(let msg) = mgr.state {
                Text(msg).foregroundColor(.red).font(.callout)
            } else {
                ProgressView().controlSize(.small)
                Text("正在启动…").foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - 归档管理

private enum ArchiveConfirmation: Identifiable {
    case delete(ArchivedConversation)
    case deleteAll(Int)
    case stopExternal(Int32)

    var id: String {
        switch self {
        case .delete(let conversation): return "delete-\(conversation.id)"
        case .deleteAll: return "delete-all"
        case .stopExternal(let pid): return "stop-external-\(pid)"
        }
    }
}

struct ArchiveManagerView: View {
    @StateObject private var store = ArchiveStore()
    @ObservedObject private var mgr = Manager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation: ArchiveConfirmation?

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
                        Button("停止外部实例") { confirmation = .stopExternal(pid) }
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
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            } else if let status = store.statusMessage {
                Label(status, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundColor(.green)
                    .textSelection(.enabled)
            }

            Text("“恢复”只取消隐藏标记；“永久删除”会先备份索引，再将日志目录移到 macOS 废纸篓。清空废纸篓后日志才不可恢复。")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button(role: .destructive) {
                    confirmation = .deleteAll(store.items.count)
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
        .onAppear { store.reload() }
        .alert(item: $confirmation) { prompt in
            switch prompt {
            case .delete(let conversation):
                return Alert(
                    title: Text("永久删除这条归档？"),
                    message: Text("“\(conversation.title)”的日志将移到废纸篓，并从 DSH 索引中移除。操作前会自动备份索引。"),
                    primaryButton: .destructive(Text("移到废纸篓")) {
                        store.delete(conversation, servicePort: mgr.port)
                    },
                    secondaryButton: .cancel()
                )
            case .deleteAll(let count):
                return Alert(
                    title: Text("清空全部归档？"),
                    message: Text("将从 DSH 索引中移除 \(count) 条归档，并把找到的日志目录移到废纸篓。操作前会自动备份索引。"),
                    primaryButton: .destructive(Text("清空归档")) {
                        store.deleteAll(servicePort: mgr.port)
                    },
                    secondaryButton: .cancel()
                )
            case .stopExternal(let pid):
                return Alert(
                    title: Text("停止外部 DSH 实例？"),
                    message: Text("将向不是由本客户端启动的 dsh 进程（pid \(pid)）发送终止信号。"),
                    primaryButton: .destructive(Text("停止")) { mgr.killExternal() },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var archiveSummary: String {
        let size = ByteCountFormatter.string(fromByteCount: store.totalByteCount, countStyle: .file)
        return "已归档 \(store.items.count) 条 · 日志 \(size)"
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

            Button("恢复") {
                store.restore(conversation, servicePort: mgr.port)
            }
            .disabled(serviceActive || store.isBusy)

            Button(role: .destructive) {
                confirmation = .delete(conversation)
            } label: {
                Text("删除")
            }
            .disabled(serviceActive || store.isBusy)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - 设置

struct SettingsView: View {
    @ObservedObject private var mgr = Manager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmKillExternal = false

    private let portFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 1
        f.maximum = 65535
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置").font(.title2).bold()

            GroupBox(label: Label("服务", systemImage: "server.rack")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text("端口:")
                        TextField("3080", value: $mgr.port, formatter: portFormatter)
                            .frame(width: 90)
                        Text("主机:")
                        TextField("127.0.0.1", text: $mgr.host)
                            .frame(width: 130)
                        Spacer()
                    }
                    HStack(spacing: 20) {
                        Toggle("打开应用时自动启动服务", isOn: $mgr.autoStart)
                        Toggle("退出应用时停止服务", isOn: $mgr.stopOnQuit)
                        Toggle("开机自启", isOn: $mgr.launchAtLogin)
                            .onChange(of: mgr.launchAtLogin) { newValue in
                                mgr.toggleLaunchAtLogin(newValue)
                            }
                    }
                    HStack(spacing: 20) {
                        Toggle("启动时自动清理无响应的残留 dsh 进程", isOn: $mgr.cleanupStaleOnStart)
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        Toggle("简化内嵌 Web UI 的插件列表", isOn: $mgr.simplifyPluginInventory)
                        Spacer()
                        Text("默认只显示用户安装；异常与全部运行单元仍可切换")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 12) {
                        Text("dsh 路径:")
                        TextField("", text: $mgr.dshPath)
                            .font(.system(.body, design: .monospaced))
                        Button("浏览…") { pickPath() }
                        if !FileManager.default.isExecutableFile(atPath: mgr.dshPath) {
                            Button("安装官方版本") { mgr.installOfficialRuntime() }
                                .disabled(mgr.isInstallingRuntime)
                        }
                        if FileManager.default.isExecutableFile(atPath: mgr.dshPath) {
                            Text("✓ 有效").foregroundColor(.green)
                        } else {
                            Text("✗ 无效").foregroundColor(.red)
                        }
                    }
                    HStack {
                        Text("修改端口/主机后，请点击「重启」让服务生效。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if case .externalRunning(let pid) = mgr.state {
                            Button(role: .destructive) { confirmKillExternal = true } label: {
                                Label("停止外部实例 (pid \(pid))", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
                .padding(4)
            }

            GroupBox(label: Label("本地模型服务", systemImage: "cpu")) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 10) {
                        Text("名称:").frame(width: 86, alignment: .trailing)
                        TextField("例如：Qwen 27B", text: $mgr.localModelName)
                    }
                    HStack(spacing: 10) {
                        Text("启动程序:").frame(width: 86, alignment: .trailing)
                        TextField("可执行文件或脚本路径", text: $mgr.localModelStartExecutable)
                            .font(.system(.body, design: .monospaced))
                        Button("浏览…") { pickLocalModelExecutable(forStop: false) }
                        Text(FileManager.default.isExecutableFile(atPath: mgr.localModelStartPath) ? "✓" : "✗")
                            .foregroundColor(FileManager.default.isExecutableFile(atPath: mgr.localModelStartPath) ? .green : .red)
                    }
                    HStack(spacing: 10) {
                        Text("启动参数:").frame(width: 86, alignment: .trailing)
                        TextField("例如：--port 8000 --model \"/路径/模型\"", text: $mgr.localModelStartArguments)
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack(spacing: 10) {
                        Text("停止程序:").frame(width: 86, alignment: .trailing)
                        TextField("可选；后台服务建议配置 stop.sh", text: $mgr.localModelStopExecutable)
                            .font(.system(.body, design: .monospaced))
                        Button("浏览…") { pickLocalModelExecutable(forStop: true) }
                    }
                    HStack(spacing: 10) {
                        Text("停止参数:").frame(width: 86, alignment: .trailing)
                        TextField("可选", text: $mgr.localModelStopArguments)
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack(spacing: 10) {
                        Text("健康检查:").frame(width: 86, alignment: .trailing)
                        TextField("可选，例如 http://127.0.0.1:<端口>/health", text: $mgr.localModelHealthURL)
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack(spacing: 10) {
                        Circle()
                            .fill(localModelStatusColor)
                            .frame(width: 9, height: 9)
                        Text(localModelStatusText)
                        Spacer()
                        Toggle("退出应用时停止本地模型", isOn: $mgr.stopLocalModelOnQuit)
                        Button(mgr.localModelState == .starting || mgr.localModelState == .ready ? "停止" : "启动") {
                            mgr.toggleLocalModel()
                        }
                        .disabled(!mgr.canToggleLocalModel)
                    }
                    Text("程序将直接以当前用户权限运行；参数不会经过 Shell，也不支持管道、重定向或命令替换。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(4)
            }

            GroupBox(label: Label("日志", systemImage: "text.alignleft")) {
                VStack(alignment: .leading, spacing: 6) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(mgr.logs.isEmpty ? "（暂无日志）" : mgr.logs)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id("logtail")
                                .padding(8)
                        }
                        .frame(height: 180)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(6)
                        .onChange(of: mgr.logs) { _ in
                            withAnimation(.none) { proxy.scrollTo("logtail", anchor: .bottom) }
                        }
                    }
                    Button("清空日志") { mgr.clearLogs() }
                        .controlSize(.small)
                }
                .padding(4)
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 720)
        .onChange(of: mgr.port) { _ in mgr.persist(); mgr.refreshExternal() }
        .onChange(of: mgr.host) { _ in mgr.persist() }
        .onChange(of: mgr.dshPath) { _ in mgr.persist() }
        .onChange(of: mgr.autoStart) { _ in mgr.persist() }
        .onChange(of: mgr.stopOnQuit) { _ in mgr.persist() }
        .onChange(of: mgr.cleanupStaleOnStart) { _ in mgr.persist() }
        .onChange(of: mgr.simplifyPluginInventory) { _ in mgr.persist() }
        .onChange(of: mgr.localModelName) { _ in mgr.persist() }
        .onChange(of: mgr.localModelStartExecutable) { _ in mgr.persist(); mgr.refreshLocalModel() }
        .onChange(of: mgr.localModelStartArguments) { _ in mgr.persist() }
        .onChange(of: mgr.localModelStopExecutable) { _ in mgr.persist() }
        .onChange(of: mgr.localModelStopArguments) { _ in mgr.persist() }
        .onChange(of: mgr.localModelHealthURL) { _ in mgr.persist(); mgr.refreshLocalModel() }
        .onChange(of: mgr.stopLocalModelOnQuit) { _ in mgr.persist() }
        .alert("停止外部实例", isPresented: $confirmKillExternal) {
            Button("停止", role: .destructive) { mgr.killExternal() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将向外部 dsh 进程发送终止信号。该进程不是由本应用启动的，确定要停止它吗？")
        }
    }

    private func pickPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择 dsh 可执行文件"
        panel.message = "请选择 dsh 命令（例如 ~/.npm/_npx/*/node_modules/.bin/dsh）"
        if panel.runModal() == .OK, let u = panel.url {
            mgr.dshPath = u.path
            mgr.persist()
        }
    }

    private var localModelStatusText: String {
        switch mgr.localModelState {
        case .stopped: return "未运行"
        case .starting: return "正在启动 \(mgr.localModelDisplayName)…"
        case .ready: return "\(mgr.localModelDisplayName) 已就绪"
        case .stopping: return "正在停止…"
        case .failed(let message): return "异常：\(message)"
        }
    }

    private var localModelStatusColor: Color {
        switch mgr.localModelState {
        case .stopped: return .gray
        case .starting, .stopping: return .orange
        case .ready: return .green
        case .failed: return .red
        }
    }

    private func pickLocalModelExecutable(forStop: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = forStop ? "选择停止程序" : "选择启动程序"
        panel.message = "请选择可信的可执行文件或带有执行权限的脚本"
        if panel.runModal() == .OK, let url = panel.url {
            if forStop {
                mgr.localModelStopExecutable = url.path
            } else {
                mgr.localModelStartExecutable = url.path
            }
            mgr.persist()
            mgr.refreshLocalModel()
        }
    }
}

// MARK: - 应用入口

@main  // 告诉程序启动入口
struct DSHLauncherApp: App {  // 定义一个结构体，遵循swiftui的app协议，这儿逻辑不是继承，更像是一种声明的实现
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // 层级：app-scene（窗口、设置窗口、菜单栏）-view（页面中的具体界面）-text、button、image
    var body: some Scene {  // 计算属性（类似于无参函数），返回一个secne协议的类型
        WindowGroup("DSH Desktop Community") {  //声明一组应用窗口，并制定窗口显示什么
            ContentView() // 创建一个contentview结构体实例
        }
        .windowResizability(.contentMinSize) // 限制窗口的最小尺寸
    }
}
