import Foundation
import SwiftUI
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

    /// 端口上有服务在监听（无论是本应用启动的还是外部实例）。
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

private enum LocalModelHealthResult {
    case healthy
    case unexpectedStatus(Int)
    case unreachable
}

/// URLSession 的完成回调与探测线程可能同时访问结果，用一个很小的锁盒避免数据竞争。
private final class LocalModelHealthProbeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: LocalModelHealthResult = .unreachable

    func store(_ result: LocalModelHealthResult) {
        lock.lock()
        value = result
        lock.unlock()
    }

    func load() -> LocalModelHealthResult {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
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
    @Published var captureModelRequests: Bool = {
        if let value = UserDefaults.standard.object(forKey: "captureModelRequests") as? Bool { return value }
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
    private var localModelHealthFailureCount = 0
    private var localModelHealthMismatchStatus: Int?
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
        d.set(captureModelRequests, forKey: "captureModelRequests")
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

    private func probeLocalModelHealth(_ url: URL, timeout: TimeInterval = 2) -> LocalModelHealthResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let semaphore = DispatchSemaphore(value: 0)
        let result = LocalModelHealthProbeBox()
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                result.store(
                    (200...399).contains(http.statusCode)
                        ? .healthy
                        : .unexpectedStatus(http.statusCode)
                )
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 1)
        task.cancel()
        return result.load()
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
            let health = self?.probeLocalModelHealth(healthURL) ?? .unreachable
            DispatchQueue.main.async {
                guard let self, self.configuredLocalModelHealthURL == healthURL,
                      self.localModelState != .stopping else { return }

                switch health {
                case .healthy:
                    self.localModelHealthFailureCount = 0
                    self.localModelHealthMismatchStatus = nil
                    self.localModelStartDeadline = nil
                    self.localModelState = .ready
                case .unexpectedStatus(let statusCode):
                    self.localModelHealthFailureCount = 0
                    self.localModelStartDeadline = nil
                    let message = "健康检查返回 HTTP \(statusCode)，端口可能被其他服务占用"
                    if self.localModelHealthMismatchStatus != statusCode
                        || self.localModelState != .failed(message) {
                        self.appendLog("✗ \(self.localModelDisplayName) \(message)：\(healthURL.absoluteString)")
                    }
                    self.localModelHealthMismatchStatus = statusCode
                    self.localModelState = .failed(message)
                case .unreachable:
                    let wasMismatch = self.localModelHealthMismatchStatus != nil
                    self.localModelHealthMismatchStatus = nil

                    if wasMismatch,
                       self.localModelProc?.isRunning != true,
                       case .failed = self.localModelState {
                        self.localModelHealthFailureCount = 0
                        self.localModelState = .stopped
                    } else if self.localModelState == .ready {
                        if self.localModelProc?.isRunning != true {
                            self.localModelHealthFailureCount = 0
                            self.localModelState = .stopped
                        } else {
                            self.localModelHealthFailureCount += 1
                            if self.localModelHealthFailureCount >= 3 {
                                self.localModelState = .failed("健康检查连续失败")
                                self.appendLog("✗ \(self.localModelDisplayName) 健康检查连续失败：\(healthURL.absoluteString)")
                            }
                        }
                    } else if self.localModelState == .starting,
                              let deadline = self.localModelStartDeadline,
                              Date() > deadline {
                        self.localModelHealthFailureCount = 0
                        self.localModelState = .failed("健康检查超时")
                        self.appendLog("✗ \(self.localModelDisplayName) 未在预期时间内通过健康检查")
                    }
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
        localModelHealthFailureCount = 0
        localModelHealthMismatchStatus = nil
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
        localModelHealthFailureCount = 0
        localModelHealthMismatchStatus = nil

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
        let processEnvironment = enrichedEnvironment()
        var dshArguments = ["web", "--host", host, "--port", "\(port)", "--no-open"]
        let inspectorOutput = requestInspectorOutputURL()
        try? FileManager.default.removeItem(at: inspectorOutput)
        if captureModelRequests {
            if let inspector = requestInspectorResources() {
                do {
                    let patch = try prepareRequestInspectorPatch(
                        moduleURL: inspector.moduleURL,
                        outputURL: inspectorOutput
                    )
                    dshArguments.insert(contentsOf: ["--patch", patch.path], at: 1)
                    appendLog("🔎 已启用模型固定输入检查器（仅本机临时缓存）")
                } catch {
                    appendLog("⚠️ 无法准备模型固定输入检查器：\(error.localizedDescription)")
                }
            } else {
                appendLog("⚠️ 未找到模型固定输入检查器资源；本次启动不会捕获固定输入")
            }
        }
        // 优先用显式 node 解释器直接运行 dsh 的 bin.js：
        // GUI 应用从 Finder/LaunchServices 启动时 PATH 往往不含任何 node，
        // 依赖 shebang `#!/usr/bin/env node` 会直接失败。
        // 显式 node + 脚本路径的方式对环境 PATH 零依赖，最稳。
        let script = resolvedScriptPath(dshPath)
        if let node = findNodeExecutable(), script.hasSuffix(".js") {
            p.executableURL = URL(fileURLWithPath: node)
            p.arguments = [script] + dshArguments
        } else {
            p.executableURL = URL(fileURLWithPath: dshPath)
            p.arguments = dshArguments
        }
        p.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        // 双保险：同时补充 PATH，覆盖直接执行分支及 dsh 内部再拉起子进程的场景
        p.environment = processEnvironment
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
        try? FileManager.default.removeItem(at: requestInspectorOutputURL())
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
