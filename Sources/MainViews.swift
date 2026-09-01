import Foundation
import SwiftUI
import AppKit

// MARK: - 主界面

struct ContentView: View {
    // 全局共享的一个manager实例，dsh状态、日志、端口、dsh路径、启动停止方法
    @ObservedObject private var mgr = Manager.shared // boserveobject是告诉界面观察这个对象，属性变化需要重新计算界面
    @State private var showSettings = false // 是否显示设置
    @State private var showArchiveManager = false // 是否显示归档管理
    @State private var showContextMemory = false // 是否显示模型上下文与长期记忆
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
        .sheet(isPresented: $showContextMemory) {
            ContextMemoryView()
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

            Button(action: { showContextMemory = true }) {
                Label("固定输入与记忆", systemImage: "brain")
                    .labelStyle(.iconOnly)
            }
            .help("查看实际 System Prompt、工具/Skill 目录、固定指令与长期记忆")

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
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.title2).bold()
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

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
                                Toggle("捕获模型固定输入（本机临时缓存）", isOn: $mgr.captureModelRequests)
                                Spacer()
                                Text("重启 DSH 后生效；不捕获普通对话和工具执行过程")
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
                                    Button(role: .destructive) {
                                        confirmKillExternal = true
                                    } label: {
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
                                Text(
                                    FileManager.default.isExecutableFile(atPath: mgr.localModelStartPath) ? "✓" : "✗"
                                )
                                .foregroundColor(
                                    FileManager.default.isExecutableFile(atPath: mgr.localModelStartPath)
                                        ? .green : .red)
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
                                Button(
                                    mgr.localModelState == .starting || mgr.localModelState == .ready ? "停止" : "启动"
                                ) {
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
                }
                .padding(18)
            }

            Divider()

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(width: 720, height: 600)
        .onChange(of: mgr.port) { _ in
            mgr.persist(); mgr.refreshExternal()
        }
        .onChange(of: mgr.host) { _ in mgr.persist() }
        .onChange(of: mgr.dshPath) { _ in mgr.persist() }
        .onChange(of: mgr.autoStart) { _ in mgr.persist() }
        .onChange(of: mgr.stopOnQuit) { _ in mgr.persist() }
        .onChange(of: mgr.cleanupStaleOnStart) { _ in mgr.persist() }
        .onChange(of: mgr.simplifyPluginInventory) { _ in mgr.persist() }
        .onChange(of: mgr.captureModelRequests) { _ in mgr.persist() }
        .onChange(of: mgr.localModelName) { _ in mgr.persist() }
        .onChange(of: mgr.localModelStartExecutable) { _ in
            mgr.persist(); mgr.refreshLocalModel()
        }
        .onChange(of: mgr.localModelStartArguments) { _ in mgr.persist() }
        .onChange(of: mgr.localModelStopExecutable) { _ in mgr.persist() }
        .onChange(of: mgr.localModelStopArguments) { _ in mgr.persist() }
        .onChange(of: mgr.localModelHealthURL) { _ in
            mgr.persist(); mgr.refreshLocalModel()
        }
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
