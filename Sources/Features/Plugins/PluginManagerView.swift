import Foundation
import SwiftUI
import AppKit
import DSHCore
import DSHUI

package struct PluginManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store: PluginManagerStore
    @ObservedObject private var manager: DSHService

    package init(store: PluginManagerStore, service: DSHService) {
        self.store = store
        self.manager = service
    }
    @State private var dialog: ThemeDialogDescriptor?
    @State private var showLog = false
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    package var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("插件管理", systemImage: "puzzlepiece.extension").font(.title2.bold())
                Spacer()
                Button("刷新") { store.reload() }.disabled(store.busy)
                Button("检查更新") { store.checkUpdates() }.disabled(store.busy || store.plugins.isEmpty)
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction).disabled(store.isMutating)
            }
            Text("用户安装的 Web 插件可单独更新；官方内置组件随 DSH 运行时升级。")
                .foregroundColor(.secondary)
            if !store.serviceAllowsChanges {
                Label("更新和恢复需要服务已停止，或由本客户端正常运行。外部实例请先停止后再操作。", systemImage: "info.circle")
                    .font(.callout).foregroundColor(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.plugins.isEmpty {
                        Text("尚未发现用户安装的 Web 插件。").foregroundColor(.secondary).padding(.vertical, 24)
                    }
                    ForEach(store.plugins) { plugin in pluginRow(plugin) }
                    if !store.backups.isEmpty {
                        Divider().padding(.vertical, 8)
                        Text("恢复备份").font(.headline)
                        Text("每份备份包含整个 Web profile 的配置和已安装插件。恢复会将所有插件回到备份时的状态；恢复前也会保存当前状态。")
                            .font(.caption).foregroundColor(.secondary)
                        ForEach(store.backups.prefix(20)) { backup in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(backup.reason).lineLimit(2)
                                    Text(backup.createdAt, style: .date) + Text(" ") + Text(backup.createdAt, style: .time)
                                }.font(.caption)
                                Spacer()
                                Button("恢复") { confirmRestore(backup) }
                                    .disabled(store.busy || !store.serviceAllowsChanges)
                            }.padding(10).background(Color.primary.opacity(0.035)).cornerRadius(8)
                        }
                        Button("在 Finder 中查看备份") { NSWorkspace.shared.open(store.backupRoot) }.font(.caption)
                    }
                }
            }
            if store.busy { ProgressView().controlSize(.small) }
            if !store.message.isEmpty { Text(store.message).font(.callout).textSelection(.enabled) }
            if let error = store.errorMessage { Text(error).foregroundColor(.red).font(.callout).textSelection(.enabled) }
            if !store.commandLog.isEmpty {
                DisclosureGroup("操作日志", isExpanded: $showLog) {
                    ScrollView { Text(store.commandLog).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(height: 100)
                }
            }
            Text("更新会短暂停止并重新启动 DSH，请在会话空闲时操作。操作期间请勿在终端同时安装或更新插件。")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(24).frame(width: 760, height: 660)
        .background(ThemeWindowBackground())
        .interactiveDismissDisabled(store.isMutating)
        .themedDialog(item: $dialog)
        .onAppear { store.reload() }
        .onReceive(timer) { _ in store.refreshInventory() }
        .onChange(of: manager.state) { _ in store.refreshInventory() }
    }

    private func pluginRow(_ plugin: ManagedPlugin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(plugin.name).font(.headline).textSelection(.enabled)
                Spacer()
                Text(store.status(for: plugin)).font(.caption).foregroundColor(.secondary)
                Button("更新") { confirmUpdate(plugin) }
                    .disabled(store.busy || !store.serviceAllowsChanges || !store.canUpdate(plugin))
            }
            HStack(spacing: 24) {
                Text("已安装：\(plugin.installedVersion ?? "未安装 / 无法读取")")
                Text("最新：\(store.latest[plugin.name] ?? (plugin.registryManaged ? "尚未检查" : "由原来源管理"))")
            }.font(.callout)
            Text("版本约束：\(plugin.requirement)").font(.caption).foregroundColor(.secondary).textSelection(.enabled)
            if !plugin.registryManaged {
                Text("本地目录、Git 或别名来源暂不支持一键更新，请按原安装来源维护。").font(.caption).foregroundColor(.secondary)
            }
            if let error = store.checkErrors[plugin.name] {
                DisclosureGroup("版本检查失败") { Text(error).font(.caption).textSelection(.enabled) }.foregroundColor(.orange)
            }
        }.padding(14).background(Color.primary.opacity(0.035)).cornerRadius(10)
    }

    private func confirmUpdate(_ plugin: ManagedPlugin) {
        guard let target = store.latest[plugin.name] else { return }
        dialog = ThemeDialogDescriptor(title: "更新 \(plugin.name)？",
            message: "将从 \(plugin.installedVersion ?? "未安装") 更新到 \(target)，可能跨越当前版本约束。客户端会备份整个 Web profile、停止服务、安装指定版本，然后启动并检查插件。",
            systemImage: "arrow.down.circle", tone: .info, primaryTitle: "备份并更新",
            primaryAction: { store.update(plugin) })
    }

    private func confirmRestore(_ backup: PluginBackup) {
        dialog = ThemeDialogDescriptor(title: "恢复整个 Web 插件环境？",
            message: "将恢复“\(backup.reason)”操作之前的配置和所有插件。当前环境会先另存为备份，恢复后将启动服务并检查加载状态。",
            systemImage: "arrow.uturn.backward", tone: .warning, primaryTitle: "备份并恢复",
            primaryAction: { store.restore(backup) })
    }
}
