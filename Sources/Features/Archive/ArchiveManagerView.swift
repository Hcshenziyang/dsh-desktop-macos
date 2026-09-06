import Foundation
import SwiftUI
import AppKit
import DSHCore
import DSHUI

package struct ArchiveManagerView: View {
    @StateObject private var store: ArchiveStore
    @ObservedObject private var mgr: DSHService

    package init(service: DSHService) {
        self.mgr = service
        _store = StateObject(wrappedValue: ArchiveStore(runtime: service))
    }
    @Environment(\.dismiss) private var dismiss
    @State private var dialog: ThemeDialogDescriptor?

    private var serviceActive: Bool {
        mgr.ownsProcess || mgr.state.portActive
    }

    package var body: some View {
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
            primaryAction: { store.delete(conversation) }
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
            primaryAction: { store.deleteAll() }
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
                store.restore(conversation)
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
