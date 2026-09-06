import Foundation
import Combine
import ServiceManagement
import Darwin

package final class DSHService: ObservableObject {
    @Published package private(set) var state: DSHState = .stopped
    @Published package var dshPath: String = ""
    @Published package var host: String = "127.0.0.1"
    @Published package var port: Int = 3080
    @Published package var autoStart: Bool = true
    @Published package var stopOnQuit: Bool = true
    @Published package var cleanupStaleOnStart: Bool = true
    @Published package var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @Published package private(set) var isInstallingRuntime: Bool = false
    @Published package private(set) var isMaintaining = false
    private var proc: Process?
    private var installProc: Process?
    private var readyTimer: Timer?
    private var watchTimer: Timer?
    private var pendingRestart = false
    private var warnedBusy = false
    private var lastHealthCheck: Date?
    private var healthFailStreak = 0

    package var url: URL {
        URL(string: "http://\(host):\(port)") ?? URL(string: "http://127.0.0.1:3080")!
    }
    /// 是否由本应用托管了子进程
    package var ownsProcess: Bool { proc != nil }
    /// 是否可以点击「启动」
    package var canStart: Bool {
        guard !isMaintaining else { return false }
        if case .stopped = state { return !dshPath.isEmpty }
        return false
    }

    private let defaults: UserDefaults
    private let prepareLaunch: () -> DSHLaunchPreparation
    private let cleanUpLaunch: () -> Void
    private let log: (String) -> Void
    private var maintenance: DSHMaintenanceToken?

    package init(defaults: UserDefaults = .standard,
                 prepareLaunch: @escaping () -> DSHLaunchPreparation = { DSHLaunchPreparation() },
                 cleanUpLaunch: @escaping () -> Void = {},
                 log: @escaping (String) -> Void = { _ in }, monitor: Bool = true) {
        self.defaults = defaults
        self.prepareLaunch = prepareLaunch
        self.cleanUpLaunch = cleanUpLaunch
        self.log = log
        dshPath = defaults.string(forKey: "dshPath") ?? resolveDshPath(defaults: defaults)
        host = defaults.string(forKey: "host") ?? "127.0.0.1"
        port = defaults.object(forKey: "port") as? Int ?? 3080
        if port == 0 { port = 3080 }
        autoStart = defaults.object(forKey: "autoStart") as? Bool ?? true
        stopOnQuit = defaults.object(forKey: "stopOnQuit") as? Bool ?? true
        cleanupStaleOnStart = defaults.object(forKey: "cleanupStaleOnStart") as? Bool ?? true
        if monitor {
            watchTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refreshExternal() }
        }
    }

    deinit { watchTimer?.invalidate(); readyTimer?.invalidate() }

    package func beginMaintenance() -> DSHMaintenanceToken? {
        guard maintenance == nil, !isInstallingRuntime else { return nil }
        let token = DSHMaintenanceToken()
        maintenance = token
        isMaintaining = true
        return token
    }

    package func endMaintenance(_ token: DSHMaintenanceToken) {
        guard maintenance == token else { return }
        maintenance = nil
        isMaintaining = false
    }

    package func reconcileStoppedState(maintenance token: DSHMaintenanceToken) {
        guard maintenance == token, !ownsProcess, listeningPid(port: port) == nil else { return }
        if case .failed = state { state = .stopped }
    }

    package func persist() {
        let d = defaults
        d.set(dshPath, forKey: "dshPath")
        d.set(host, forKey: "host")
        d.set(port, forKey: "port")
        d.set(autoStart, forKey: "autoStart")
        d.set(stopOnQuit, forKey: "stopOnQuit")
        d.set(cleanupStaleOnStart, forKey: "cleanupStaleOnStart")
    }

    private func appendLog(_ message: String) { log(message) }


    // MARK: 安装官方 DSH 运行时

    /// 用户主动点击后，通过 npm 安装官方 @deepseek-ai/dsh 到稳定的用户目录。
    /// 使用 Process 参数数组而不是 shell 字符串，避免命令注入和 PATH 差异。
    package func installOfficialRuntime() {
        guard !isInstallingRuntime, !isMaintaining else { return }
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
    package func startIfNeeded() {
        guard !isMaintaining else { return }
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
        guard !isMaintaining else { return }
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

    package func refreshExternal() {
        guard proc == nil else { return }
        let pid = listeningPid(port: port)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.handleExternalPoll(pid: pid)
        }
    }

    /// 端口轮询：发现/未发现 dsh 进程时的处理（主线程）
    private func handleExternalPoll(pid: Int32?) {
        guard !isMaintaining else { return }
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
        guard !isMaintaining else { return }
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

    package func start(maintenance token: DSHMaintenanceToken? = nil) {
        guard maintenance == token else { return }
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
        let additions = prepareLaunch()
        dshArguments.insert(contentsOf: additions.arguments, at: 1)
        additions.messages.forEach(appendLog)
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

    package func stop(maintenance token: DSHMaintenanceToken? = nil) {
        guard maintenance == token else { return }
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

    package func restart() {
        guard !isMaintaining else { return }
        guard proc != nil else {
            start()
            return
        }
        pendingRestart = true
        stop()
    }

    package func killExternal() {
        guard !isMaintaining else { return }
        guard case .externalRunning(let pid) = state else { return }
        state = .stopped
        killProcess(pid: pid, label: "停止外部 dsh 实例")
    }

    /// 终止进程：先 SIGTERM，4 秒后仍存活则 SIGKILL；结束后刷新端口状态
    private func killProcess(pid: Int32, label: String) {
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
    private func forceFreePort(pid: Int32, port: Int, label: String) -> Bool {
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
        cleanUpLaunch()
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
    package func terminateOnQuit() {
        installProc?.terminate()
        guard stopOnQuit else { return }
        if let p = proc {
            p.terminate()
        }
    }

    // MARK: 开机自启

    package func toggleLaunchAtLogin(_ on: Bool) {
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
