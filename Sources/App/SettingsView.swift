import Foundation
import SwiftUI
import AppKit
import DSHCore
import DSHUI
import DSHWeb
import LocalModelFeature
import ArchiveFeature
import PluginsFeature
import InspectorFeature
import ThemesFeature
struct SettingsView: View {
    @ObservedObject private var mgr: DSHService
    @ObservedObject private var activityLog: ActivityLog
    @ObservedObject private var pluginPreferences: PluginPreferences
    @ObservedObject private var inspectorPreferences: InspectorPreferences
    private let localModel: LocalModelService

    init(container: AppContainer) {
        mgr = container.runtime
        activityLog = container.activityLog
        pluginPreferences = container.pluginPreferences
        inspectorPreferences = container.inspectorPreferences
        localModel = container.localModel
    }
    @Environment(\.dismiss) private var dismiss
    @State private var dialog: ThemeDialogDescriptor?

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
            .background(ThemeChromeBackground())

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
                                Toggle("简化内嵌 Web UI 的插件列表", isOn: $pluginPreferences.simplifyPluginInventory)
                                Spacer()
                                Text("默认只显示用户安装；异常与全部运行单元仍可切换")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 12) {
                                Toggle("捕获模型固定输入（本机临时缓存）", isOn: $inspectorPreferences.captureModelRequests)
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
                                        presentExternalStopDialog()
                                    } label: {
                                        Label("停止外部实例 (pid \(pid))", systemImage: "xmark.circle")
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }

                    LocalModelSettingsView(service: localModel)

                    GroupBox(label: Label("日志", systemImage: "text.alignleft")) {
                        VStack(alignment: .leading, spacing: 6) {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    Text(activityLog.text.isEmpty ? "（暂无日志）" : activityLog.text)
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
                                .onChange(of: activityLog.text) { _ in
                                    withAnimation(.none) { proxy.scrollTo("logtail", anchor: .bottom) }
                                }
                            }
                            Button("清空日志") { activityLog.clear() }
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
            .background(ThemeChromeBackground())
        }
        .frame(width: 720, height: 600)
        .background(ThemeWindowBackground())
        .onChange(of: mgr.port) { _ in
            mgr.persist(); mgr.refreshExternal()
        }
        .onChange(of: mgr.host) { _ in mgr.persist() }
        .onChange(of: mgr.dshPath) { _ in mgr.persist() }
        .onChange(of: mgr.autoStart) { _ in mgr.persist() }
        .onChange(of: mgr.stopOnQuit) { _ in mgr.persist() }
        .onChange(of: mgr.cleanupStaleOnStart) { _ in mgr.persist() }
        .themedDialog(item: $dialog)
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

    private func presentExternalStopDialog() {
        dialog = ThemeDialogDescriptor(
            title: "停止外部实例？",
            message: "将向外部 dsh 进程发送终止信号。该进程不是由本应用启动的，确定要停止它吗？",
            systemImage: "exclamationmark.octagon.fill",
            tone: .danger,
            primaryTitle: "停止",
            primaryRole: .destructive,
            primaryAction: { mgr.killExternal() }
        )
    }

}
