import Foundation
import Combine
import DSHCore

@MainActor
package final class PluginManagerStore: ObservableObject {
    let runtime: DSHService
    private var maintenanceToken: DSHMaintenanceToken?

    package init(runtime: DSHService) { self.runtime = runtime }
    @Published private(set) var plugins: [ManagedPlugin] = []
    @Published private(set) var latest: [String: String] = [:]
    @Published private(set) var checkErrors: [String: String] = [:]
    @Published private(set) var backups: [PluginBackup] = []
    @Published private(set) var isChecking = false
    @Published private(set) var isMutating = false
    @Published private(set) var message = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var commandLog = ""
    @Published private(set) var inventory: PluginInventorySnapshot?
    let profile = dshHomeDirectoryURL().appendingPathComponent("profiles/web", isDirectory: true)
    let backupRoot = dshHomeDirectoryURL().appendingPathComponent("backups/plugin-manager/web", isDirectory: true)

    var busy: Bool { isChecking || isMutating }

    func reload() {
        guard !busy else { return }
        do { try reloadFiles() }
        catch { errorMessage = error.localizedDescription }
        refreshInventory()
    }

    private func reloadFiles() throws {
        backups = PluginFiles.backups(root: backupRoot, profile: profile)
        let newPlugins = try PluginFiles.load(profile: profile)
        // A changed source or installed version invalidates any prior query.
        for plugin in newPlugins where !plugins.contains(plugin) {
            latest[plugin.name] = nil
            checkErrors[plugin.name] = nil
        }
        plugins = newPlugins
    }

    func refreshInventory() {
        guard case .running(let pid) = runtime.state,
              let data = try? Data(contentsOf: pluginInventoryOutputURL()),
              let snapshot = try? JSONDecoder().decode(PluginInventorySnapshot.self, from: data),
              snapshot.pid == pid,
              abs(Date().timeIntervalSince1970 - snapshot.updatedAt / 1000) < 5 else {
            inventory = nil
            return
        }
        inventory = snapshot
    }

    func status(for plugin: ManagedPlugin) -> String {
        if let inventory { return inventory.status(for: plugin.name).displayName }
        switch runtime.state {
        case .stopped: return "服务已停止"
        case .externalRunning: return "外部实例 · 状态未验证"
        case .starting: return "服务启动中"
        case .stopping: return "服务停止中"
        case .failed: return "服务异常"
        case .running: return "运行状态暂不可用"
        }
    }

    func canUpdate(_ plugin: ManagedPlugin) -> Bool {
        guard plugin.registryManaged, let target = latest[plugin.name],
              PluginVersions.valid(target) else { return false }
        guard let installed = plugin.installedVersion else { return true }
        return PluginVersions.isNewer(target, than: installed)
    }

    private func pnpmExecutable() throws -> String {
        for directory in (enrichedEnvironment()["PATH"] ?? "").split(separator: ":") {
            let path = String(directory) + "/pnpm"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        throw PluginOperationError(message: "未找到 pnpm，请先安装 pnpm 后再管理插件。")
    }

    private var commandEnvironment: [String: String] {
        var environment = enrichedEnvironment()
        environment["DSH_HOME"] = profile.deletingLastPathComponent().deletingLastPathComponent().path
        environment["CI"] = "true"
        environment["NO_COLOR"] = "1"
        environment["npm_config_fetch_timeout"] = "30000"
        environment["npm_config_fetch_retries"] = "1"
        return environment
    }

    func checkUpdates() {
        guard !busy else { return }
        reload()
        guard !plugins.isEmpty else { return }
        isChecking = true
        errorMessage = nil
        latest = [:]
        checkErrors = [:]
        Task {
            defer { isChecking = false }
            do {
                let pnpm = try pnpmExecutable()
                for plugin in plugins where plugin.registryManaged {
                    message = "正在检查 \(plugin.name)…"
                    do {
                        // Call pnpm directly for reads: dsh plugin reconciles the
                        // manifest even after read-only commands that exit zero.
                        let result = try await ProcessCommand.run(executable: pnpm,
                            arguments: ["view", plugin.name, "dist-tags.latest", "--json"],
                            directory: profile, environment: commandEnvironment, timeout: 70)
                        guard result.status == 0,
                              let data = result.output.data(using: .utf8),
                              let version = try? JSONDecoder().decode(String.self, from: data),
                              PluginVersions.valid(version) else {
                            throw PluginOperationError(message: "版本查询失败：\(result.output.suffix(1500))")
                        }
                        latest[plugin.name] = version
                    } catch { checkErrors[plugin.name] = error.localizedDescription }
                }
                message = checkErrors.isEmpty ? "版本检查完成" : "部分插件检查失败，可重试或展开错误详情。"
            } catch { errorMessage = error.localizedDescription; message = "版本检查失败" }
        }
    }

    var serviceAllowsChanges: Bool {
        guard !runtime.dshPath.isEmpty, !runtime.isInstallingRuntime, !runtime.isMaintaining else { return false }
        switch runtime.state {
        case .stopped, .failed: return true
        case .running: return runtime.ownsProcess
        default: return false
        }
    }

    func update(_ plugin: ManagedPlugin) {
        guard !busy, serviceAllowsChanges, canUpdate(plugin), let target = latest[plugin.name] else { return }
        perform(reason: "更新 \(plugin.name) 至 \(target)", package: plugin.name) {
            let current = try PluginFiles.load(profile: self.profile)
            guard current.contains(plugin) else {
                throw PluginOperationError(message: "插件已被其他操作修改，请刷新后重新检查版本。")
            }
            let result = try await self.runDSH(["plugin", "--profile", "web", "update", "\(plugin.name)@\(target)"])
            self.commandLog = result.output
            guard result.status == 0 else {
                throw PluginOperationError(message: "插件更新失败（退出码 \(result.status)），可查看操作日志并恢复备份。")
            }
            guard try PluginFiles.load(profile: self.profile).first(where: { $0.name == plugin.name })?.installedVersion == target else {
                throw PluginOperationError(message: "安装后的版本与目标版本不一致，请恢复备份后重试。")
            }
        }
    }

    func restore(_ backup: PluginBackup) {
        guard !busy, serviceAllowsChanges else { return }
        perform(reason: "恢复备份：\(backup.reason)", package: nil) {
            let profile = self.profile, root = self.backupRoot
            try await Task.detached(priority: .userInitiated) {
                try PluginFiles.restore(backup, profile: profile, root: root)
            }.value
        }
    }

    private func runDSH(_ arguments: [String]) async throws -> ProcessCommandResult {
        let path = runtime.dshPath
        let script = resolvedScriptPath(path)
        if script.hasSuffix(".js"), let node = findNodeExecutable() {
            return try await ProcessCommand.run(executable: node, arguments: [script] + arguments,
                                               directory: profile, environment: commandEnvironment)
        }
        return try await ProcessCommand.run(executable: path, arguments: arguments,
                                           directory: profile, environment: commandEnvironment)
    }

    private func perform(reason: String, package: String?, action: @escaping () async throws -> Void) {
        guard let token = runtime.beginMaintenance() else { return }
        isMutating = true
        maintenanceToken = token
        errorMessage = nil
        commandLog = ""
        message = "准备\(reason)…"
        Task {
            defer { isMutating = false; runtime.endMaintenance(token); maintenanceToken = nil }
            var savedBackup: PluginBackup?
            do {
                if package != nil { _ = try pnpmExecutable() }
                let lock = try PluginProfileLock(profile: profile)
                defer { withExtendedLifetime(lock) {} }
                try await stopService()
                message = "正在备份配置、锁文件和已安装插件…"
                let profile = self.profile, root = backupRoot
                savedBackup = try await Task.detached(priority: .userInitiated) {
                    try PluginFiles.backup(profile: profile, root: root, reason: reason, allowIncomplete: package == nil)
                }.value
                backups = PluginFiles.backups(root: backupRoot, profile: profile)
                message = "正在\(reason)…"
                try await action()
                try reloadFiles()
                message = "正在启动 DSH 并检查插件加载状态…"
                let fullyLoaded = try await startAndVerify(package: package)
                message = fullyLoaded
                    ? "\(reason)完成，服务与插件加载检查通过。"
                    : "\(reason)完成，服务已启动；部分模块已运行，其余模块仍在等待依赖，请查看插件状态。"
            } catch {
                // Do not boot a potentially half-written dependency tree. Leave
                // the exact failure and a persistent recovery entry visible.
                errorMessage = error.localizedDescription
                message = savedBackup == nil ? "操作未完成" : "操作未完成，更新前的完整备份已保留，可在下方恢复。"
                try? reloadFiles()
            }
        }
    }

    private func stopService() async throws {
        let manager = runtime
        if case .externalRunning = manager.state {
            throw PluginOperationError(message: "请先停止外部 DSH 实例，再由客户端启动。")
        }
        if manager.ownsProcess {
            message = "正在停止 DSH 服务…"
            manager.stop(maintenance: maintenanceToken)
        }
        if case .failed = manager.state, !manager.ownsProcess, listeningPid(port: manager.port) == nil {
            if let token = maintenanceToken { manager.reconcileStoppedState(maintenance: token) }
        }
        for _ in 0..<40 {
            if !manager.ownsProcess, manager.state == .stopped { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard !manager.ownsProcess, manager.state == .stopped,
              listeningPid(port: manager.port) == nil else {
            throw PluginOperationError(message: "DSH 服务尚未完全停止，未修改插件。")
        }
        inventory = nil
    }

    private func startAndVerify(package: String?) async throws -> Bool {
        let manager = runtime
        manager.start(maintenance: maintenanceToken)
        var partialObservations = 0
        for _ in 0..<150 {
            if case .failed(let reason) = manager.state { throw PluginOperationError(message: "服务启动失败：\(reason)") }
            if manager.state == .stopped { throw PluginOperationError(message: "DSH 启动后退出，请查看客户端日志并恢复备份。") }
            if case .externalRunning = manager.state { throw PluginOperationError(message: "端口被外部实例占用，无法验证更新。") }
            refreshInventory()
            if let inventory {
                let targets = package.map { [$0] } ?? plugins.map(\.name)
                let states = targets.map { inventory.status(for: $0) }
                if states.contains(.failed) {
                    throw PluginOperationError(message: "服务已启动，但插件加载失败，请查看客户端日志并恢复备份。")
                }
                if states.allSatisfy(\.isComplete) { return true }
                if states.allSatisfy(\.isSettled) {
                    partialObservations += 1
                    // Allow startup dependencies time to settle. A partially
                    // active bundle is reported as partial, never all healthy.
                    if partialObservations >= 10 { return false }
                } else { partialObservations = 0 }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw PluginOperationError(message: "插件加载验证超时；服务可能已启动，但未确认全部目标运行单元正常。可查看日志或恢复备份。")
    }
}
