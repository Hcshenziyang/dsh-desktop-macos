import DSHCore
import DSHUI
import DSHWeb
import LocalModelFeature
import ArchiveFeature
import PluginsFeature
import InspectorFeature
import ThemesFeature
import Foundation
import SwiftUI
import AppKit

// MARK: - 主界面

struct ContentView: View {
    // 应用层注入运行时；各功能持有自己的状态。
    @ObservedObject private var mgr: DSHService
    let container: AppContainer
    @ObservedObject private var pluginPreferences: PluginPreferences
    @ObservedObject private var inspectorPreferences: InspectorPreferences

    init(container: AppContainer) {
        self.container = container
        self.mgr = container.runtime
        self.pluginPreferences = container.pluginPreferences
        self.inspectorPreferences = container.inspectorPreferences
    }
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var showSettings = false // 是否显示设置
    @State private var showArchiveManager = false // 是否显示归档管理
    @State private var showPluginManager = false
    @State private var showContextMemory = false // 是否显示模型上下文与长期记忆
    @State private var showThemeSettings = false // 是否显示主题与壁纸设置
    @State private var dialog: ThemeDialogDescriptor? // 当前主题化确认框

    var body: some View {
        VStack(spacing: 0) { // 垂直排列
            toolbar // 工具栏
            Divider() // 分割线
            ZStack { // 主要内容，zstack 重叠容器
                if mgr.state.webReady { // if else 只显示一个界面，检查mgr状态，可访问/不可访问
                    WebView(url: mgr.url,
                            enhancements: container.webEnhancements(theme: themeStore.webSnapshot),
                            resourceHandlers: [WebResourceHandler(scheme: ThemeAssetRepository.scheme, handler: ThemeAssetSchemeHandler())])
                } else {
                    placeholderView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(ThemeWindowBackground())
        .tint(themeStore.appAccentColor)
        .onAppear { mgr.startIfNeeded() }
        .sheet(isPresented: $showSettings) {
            SettingsView(container: container)
        }
        .sheet(isPresented: $showArchiveManager) {
            ArchiveManagerView(service: mgr)
        }
        .sheet(isPresented: $showPluginManager) {
            PluginManagerView(store: container.plugins, service: mgr)
        }
        .sheet(isPresented: $showContextMemory) {
            ContextMemoryView(service: mgr, preferences: inspectorPreferences)
        }
        .sheet(isPresented: $showThemeSettings) {
            ThemeSettingsView(isPresented: $showThemeSettings)
        }
        .themedDialog(item: $dialog)
    }

    // MARK: 工具栏

    private var toolbar: some View {
        HStack(spacing: 10) {
            ThemedStatusIndicator(color: statusColor, isAnimating: serviceStatusIsAnimating)
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
            .disabled(!mgr.ownsProcess || mgr.isMaintaining)

            Button(action: { mgr.restart() }) {
                Label("重启", systemImage: "arrow.clockwise")
            }
            .disabled(!mgr.ownsProcess || mgr.isMaintaining)

            Divider().frame(height: 18)

            LocalModelToolbarButton(service: container.localModel)

            if case .externalRunning(let pid) = mgr.state {
                Button(action: { presentExternalStopDialog() }) {
                    ThemedToolbarIcon(systemName: "xmark.circle", label: "接管并停止")
                }
                .buttonStyle(.plain)
                .help("停止由其他方式启动的 dsh (pid \(pid))")
            }

            Divider().frame(height: 18)

            Button(action: { showArchiveManager = true }) {
                ThemedToolbarIcon(systemName: "archivebox", label: "归档管理")
            }
            .buttonStyle(.plain)
            .help("查看、恢复或清理已归档会话")

            Button(action: { showPluginManager = true }) {
                ThemedToolbarIcon(systemName: "puzzlepiece.extension", label: "插件管理")
            }
            .buttonStyle(.plain)
            .help("检查插件更新、查看运行状态或恢复旧版本")

            Button(action: { showContextMemory = true }) {
                ThemedToolbarIcon(systemName: "brain", label: "固定输入与记忆")
            }
            .buttonStyle(.plain)
            .help("查看实际 System Prompt、工具/Skill 目录、固定指令与长期记忆")

            Button(action: { showThemeSettings = true }) {
                ThemedToolbarIcon(
                    systemName: "paintpalette",
                    label: "主题与壁纸",
                    isActive: themeStore.hasActiveSkin
                )
            }
            .buttonStyle(.plain)
            .help("配置客户端配色、强调色与静态壁纸")

            Button(action: { showSettings = true }) {
                ThemedToolbarIcon(systemName: "gearshape", label: "设置")
            }
            .buttonStyle(.plain)
            .help("打开客户端设置")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ThemeChromeBackground())
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

    private var serviceStatusIsAnimating: Bool {
        if mgr.isInstallingRuntime { return true }
        switch mgr.state {
        case .starting, .stopping: return true
        default: return false
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
                    ThemedStatusBanner(message: msg, tone: .danger)
                        .frame(maxWidth: 520)
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
                ThemedStatusBanner(message: msg, tone: .danger)
                    .frame(maxWidth: 520)
            } else {
                ProgressView().controlSize(.small)
                Text("正在启动…").foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeWindowBackground())
    }
}
