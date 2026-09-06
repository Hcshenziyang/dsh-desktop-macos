import Foundation
import Combine
import DSHCore

package enum LocalModelState: Equatable {
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


package final class LocalModelService: ObservableObject {
    @Published package private(set) var localModelState: LocalModelState = .stopped
    @Published package var localModelName: String = "本地模型"
    @Published package var localModelStartExecutable: String = ""
    @Published package var localModelStartArguments: String = ""
    @Published package var localModelStopExecutable: String = ""
    @Published package var localModelStopArguments: String = ""
    @Published package var localModelHealthURL: String = ""
    @Published package var stopLocalModelOnQuit = true
    private var localModelProc: Process?
    private var localModelStopProc: Process?
    private var localModelStartDeadline: Date?
    private var localModelHealthFailureCount = 0
    private var localModelHealthMismatchStatus: Int?
    package var localModelDisplayName: String {
        let trimmed = localModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "本地模型" : trimmed
    }
    package var localModelStartPath: String { expandedUserPath(localModelStartExecutable) }
    package var localModelStopPath: String { expandedUserPath(localModelStopExecutable) }
    package var canStartLocalModel: Bool {
        guard FileManager.default.isExecutableFile(atPath: localModelStartPath) else { return false }
        switch localModelState {
        case .stopped, .failed: return true
        case .starting, .ready, .stopping: return false
        }
    }
    package var canStopLocalModel: Bool {
        let hasTrackedProcess = localModelProc?.isRunning == true
        let hasStopExecutable = FileManager.default.isExecutableFile(atPath: localModelStopPath)
        guard hasTrackedProcess || hasStopExecutable else { return false }
        switch localModelState {
        case .starting, .ready: return true
        case .stopped, .stopping, .failed: return false
        }
    }
    package var canToggleLocalModel: Bool { canStartLocalModel || canStopLocalModel }

    private let defaults: UserDefaults
    private let log: (String) -> Void
    private var watchTimer: Timer?

    package init(defaults: UserDefaults = .standard, log: @escaping (String) -> Void = { _ in }, monitor: Bool = true) {
        self.defaults = defaults
        self.log = log
        loadPreferences()
        if monitor {
            watchTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refreshLocalModel() }
            DispatchQueue.main.async { [weak self] in self?.refreshLocalModel() }
        }
    }

    deinit { watchTimer?.invalidate() }

    private func appendLog(_ message: String) { log(message) }

    private func loadPreferences() {
        localModelName = defaults.string(forKey: "localModelName") ?? "本地模型"
        localModelStartExecutable = defaults.string(forKey: "localModelStartExecutable") ?? ""
        localModelStartArguments = defaults.string(forKey: "localModelStartArguments") ?? ""
        localModelStopExecutable = defaults.string(forKey: "localModelStopExecutable") ?? ""
        localModelStopArguments = defaults.string(forKey: "localModelStopArguments") ?? ""
        localModelHealthURL = defaults.string(forKey: "localModelHealthURL") ?? ""
        stopLocalModelOnQuit = defaults.object(forKey: "stopLocalModelOnQuit") as? Bool ?? true
    }

    package func persist() {
        let d = defaults
        d.set(localModelName, forKey: "localModelName")
        d.set(localModelStartExecutable, forKey: "localModelStartExecutable")
        d.set(localModelStartArguments, forKey: "localModelStartArguments")
        d.set(localModelStopExecutable, forKey: "localModelStopExecutable")
        d.set(localModelStopArguments, forKey: "localModelStopArguments")
        d.set(localModelHealthURL, forKey: "localModelHealthURL")
        d.set(stopLocalModelOnQuit, forKey: "stopLocalModelOnQuit")
    }


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

    package func refreshLocalModel() {
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

    package func toggleLocalModel() {
        switch localModelState {
        case .starting, .ready: stopLocalModel()
        case .stopped, .failed: startLocalModel()
        case .stopping: break
        }
    }

    package func startLocalModel() {
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

    package func stopLocalModel() {
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

    package func terminateOnQuit() {
        localModelStopProc?.terminate()
        guard stopLocalModelOnQuit else { return }
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
}
