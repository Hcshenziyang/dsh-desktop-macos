import Foundation
import SwiftUI
import AppKit
import Combine
import DSHCore
import DSHUI

package struct ContextMemoryView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case fixedInput = "模型固定输入"
        case memory = "长期记忆"
        var id: String { rawValue }
    }

    @StateObject private var store = ContextMemoryStore()
    @ObservedObject private var mgr: DSHService

    @ObservedObject private var preferences: InspectorPreferences

    package init(service: DSHService, preferences: InspectorPreferences) {
        self.mgr = service
        self.preferences = preferences
    }
    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .fixedInput
    @State private var selectedRequestId: String?
    @State private var selectedWorkspacePath: String?
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    package var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch section {
                case .fixedInput: fixedInputBrowser
                case .memory: memoryBrowser
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 980, idealWidth: 1120, minHeight: 640, idealHeight: 740)
        .background(ThemeWindowBackground())
        .onAppear { store.reload() }
        .onReceive(refreshTimer) { _ in store.reload() }
        .onChange(of: store.requests) { requests in
            if !requests.contains(where: { $0.id == selectedRequestId }) {
                selectedRequestId = requests.first?.id
            }
        }
        .onChange(of: store.memoryWorkspaces) { workspaces in
            if !workspaces.contains(where: { $0.path == selectedWorkspacePath }) {
                selectedWorkspacePath = workspaces.first?.path
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("模型固定输入与记忆").font(.title2).bold()
                Text("只展示实际送入模型的固定指令目录；对话和工具过程请使用 DSH 轨迹")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Picker("", selection: $section) {
                ForEach(Section.allCases) { section in Text(section.rawValue).tag(section) }
            }
            .pickerStyle(.segmented)
            .frame(width: 270)
            Button(action: { store.reload() }) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(store.isLoading)
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(ThemeChromeBackground())
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(store.issues, id: \.self) { issue in
                ThemedStatusBanner(message: issue, tone: .danger)
            }
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                Text("不保存普通对话、模型回复、工具调用或工具结果；固定输入缓存仅位于本机，并在客户端托管的 DSH 停止时删除。")
                Spacer()
                if let date = store.lastLoadedAt {
                    Text("更新于 \(date.formatted(date: .omitted, time: .standard))")
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(ThemeChromeBackground())
    }

    // MARK: 模型固定输入

    private var fixedInputBrowser: some View {
        Group {
            if store.requests.isEmpty {
                fixedInputEmptyState
            } else {
                HSplitView {
                    List(store.requests, selection: $selectedRequestId) { request in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(request.positionTitle).fontWeight(.medium)
                                Spacer()
                                if request.memoryProfile != nil {
                                    Image(systemName: "brain").foregroundColor(.green)
                                }
                            }
                            Text(request.routeTitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Text("系统段 \(request.promptSections.count) · 工具 \(request.tools.count) · Skill \(request.skills.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(request.capturedAt.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .tag(request.id)
                    }
                    .frame(minWidth: 250, idealWidth: 290, maxWidth: 350)

                    if let request = selectedRequest {
                        FixedInputDetailView(request: request)
                            .frame(minWidth: 620)
                    } else {
                        Text("请选择一次模型请求").foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private var selectedRequest: CapturedFixedInput? {
        store.requests.first { $0.id == selectedRequestId } ?? store.requests.first
    }

    private var fixedInputEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: preferences.captureModelRequests ? "doc.text.magnifyingglass" : "eye.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(fixedInputEmptyTitle).font(.headline)
            Text(fixedInputEmptyDescription)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 600)
            if !preferences.captureModelRequests {
                Button("在设置中启用") { preferences.captureModelRequests = true }
            }
            Text("缓存位置：\(store.inspectorURL.path)")
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var fixedInputEmptyTitle: String {
        if !preferences.captureModelRequests { return "模型固定输入捕获已关闭" }
        if case .externalRunning = mgr.state { return "当前外部 DSH 没有挂载检查器" }
        if mgr.state.webReady { return "等待下一次模型请求" }
        return "启动 DSH 后开始捕获"
    }

    private var fixedInputEmptyDescription: String {
        if !preferences.captureModelRequests { return "启用后重启 DSH。检查器只观察固定输入，不修改提示词或模型响应。" }
        if case .externalRunning = mgr.state {
            return "外部实例不是由本客户端带检查器启动的。停止外部实例，再从客户端启动 DSH 后即可查看。"
        }
        if mgr.state.webReady { return "发送一条新消息后，这里会显示最终 System Prompt、工具目录、Skill 目录和附加固定指令。" }
        return "检查器随客户端托管的 DSH 一起加载，不会修改 DSH 安装目录或用户 profile。"
    }

    // MARK: 长期记忆

    private var memoryBrowser: some View {
        Group {
            if store.memoryWorkspaces.isEmpty {
                memoryEmptyState
            } else {
                HSplitView {
                    List(store.memoryWorkspaces, selection: $selectedWorkspacePath) { workspace in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workspace.title).fontWeight(.medium)
                            Text("Profile \(workspace.profile.entries.count) · Facts \(workspace.facts.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(workspace.path)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 4)
                        .tag(workspace.path)
                    }
                    .frame(minWidth: 250, idealWidth: 290, maxWidth: 350)

                    if let workspace = selectedWorkspace {
                        MemoryWorkspaceDetailView(workspace: workspace, selectedRequest: selectedRequest)
                            .frame(minWidth: 620)
                    }
                }
            }
        }
    }

    private var selectedWorkspace: MemoryWorkspaceRecord? {
        store.memoryWorkspaces.first { $0.path == selectedWorkspacePath } ?? store.memoryWorkspaces.first
    }

    private var memoryEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.system(size: 42))
                .foregroundColor(.secondary)
            Text(store.memoryPluginInstalled ? "长期记忆库尚未产生记录" : "未检测到 dsh-native-memory")
                .font(.headline)
            Text(store.memoryPluginInstalled
                 ? "插件已经安装，但 dsh_memory.json 会在第一次实际写入 Profile 或 Fact 后才创建。"
                 : "当前页面读取 dsh-native-memory 的本地 storage-domain；安装并写入记忆后会自动显示。")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 560)
            Text("记忆文件：\(store.memoryURL.path)")
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

// MARK: - 固定输入详情

private struct FixedInputDetailView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case system = "System Prompt"
        case tools = "工具目录"
        case skills = "Skill 目录"
        case instructions = "固定指令"
        var id: String { rawValue }
    }

    let request: CapturedFixedInput
    @State private var tab: Tab = .system

    package var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(request.positionTitle).font(.title3).bold()
                        Text(request.routeTitle).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { copyToPasteboard(copyValue) }) {
                        Label("复制当前页", systemImage: "doc.on.doc")
                    }
                }
                HStack(spacing: 12) {
                    Label("\(request.promptSections.count) 个系统段", systemImage: "text.alignleft")
                    Label("\(request.tools.count) 个工具", systemImage: "wrench.and.screwdriver")
                    Label("\(request.skills.count) 个 Skill", systemImage: "books.vertical")
                    Label("\(request.fixedInstructions.count) 条附加指令", systemImage: "doc.badge.gearshape")
                    if let effort = request.reasoningEffort {
                        Label(effort, systemImage: "dial.medium")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                if let cwd = request.cwd {
                    Text(cwd).font(.caption2.monospaced()).foregroundColor(.secondary).textSelection(.enabled)
                }
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { tab in Text(tab.rawValue).tag(tab) }
                }
                .pickerStyle(.segmented)
            }
            .padding(14)
            Divider()
            tabContent
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .system: systemPromptView
        case .tools: toolCatalogView
        case .skills: skillCatalogView
        case .instructions: fixedInstructionView
        }
    }

    private var systemPromptView: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox(label: Label("最终实际发送的 System Prompt", systemImage: "paperplane")) {
                    Text(request.systemPrompt.isEmpty ? "（本次请求没有 System Prompt）" : request.systemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }

                if let memory = request.memoryProfile {
                    GroupBox(label: Label("其中包含的 Memory Profile", systemImage: "brain")) {
                        Text(memory)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.green)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                }

                if !request.promptSections.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("DSH 具名组成段", systemImage: "square.stack.3d.up")
                            .font(.headline)
                        if !request.promptSectionsMatchFinal {
                            Label("组成段来自组装注册表；上方最终全文是实际发送值，应以它为准。", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        ForEach(request.promptSections) { section in
                            DisclosureGroup {
                                Text(section.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                            } label: {
                                Text(section.name)
                                    .font(.system(.body, design: .monospaced).weight(.medium))
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private var toolCatalogView: some View {
        Group {
            if request.tools.isEmpty {
                fixedInputEmpty(
                    icon: "wrench.and.screwdriver",
                    title: "本次请求没有发送工具目录",
                    detail: "这表示最终 Provider 请求中的 tools 数组为空。"
                )
            } else {
                List(request.tools) { tool in
                    DisclosureGroup {
                        Text(tool.rawJSON)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.vertical, 6)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tool.name)
                                .font(.system(.body, design: .monospaced).weight(.medium))
                            if !tool.description.isEmpty {
                                Text(tool.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var skillCatalogView: some View {
        Group {
            if request.skills.isEmpty && request.skillCatalogText.isEmpty {
                fixedInputEmpty(
                    icon: "books.vertical",
                    title: "本次请求没有发送 Skill 目录",
                    detail: "可能是当前 Agent 没有模型可调用的 Skill，或最终工具视图中没有 skill 工具。"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if !request.skills.isEmpty {
                            Text("当前有效目录 · \(request.skills.count) 项")
                                .font(.headline)
                            ForEach(request.skills) { skill in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(skill.name)
                                        .font(.system(.body, design: .monospaced).weight(.semibold))
                                    Text(skill.description.isEmpty ? "（没有目录说明）" : skill.description)
                                        .foregroundColor(skill.description.isEmpty ? .secondary : .primary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(11)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        if !request.skillCatalogText.isEmpty {
                            GroupBox(label: Label("最终请求中实际发送的目录原文", systemImage: "paperplane")) {
                                Text(request.skillCatalogText)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private var fixedInstructionView: some View {
        Group {
            if request.fixedInstructions.isEmpty {
                fixedInputEmpty(
                    icon: "doc.badge.gearshape",
                    title: "没有其他固定指令",
                    detail: "本页只收录 AGENTS.md 和已显式加载的 Skill 正文；普通上下文和插件运行提示不会在这里重复展示。"
                )
            } else {
                List(request.fixedInstructions) { instruction in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(instruction.text)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                            Divider()
                            Text("来源元数据")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Text(instruction.sourceJSON)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 6)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(instruction.title).fontWeight(.medium)
                            Text(instruction.source)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var copyValue: String {
        switch tab {
        case .system: return request.systemPrompt
        case .tools: return request.tools.map(\.rawJSON).joined(separator: "\n\n")
        case .skills: return request.skillCatalogText
        case .instructions: return request.fixedInstructions.map { $0.text }.joined(separator: "\n\n")
        }
    }
}

private func fixedInputEmpty(icon: String, title: String, detail: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: icon).font(.system(size: 36)).foregroundColor(.secondary)
        Text(title).font(.headline)
        Text(detail)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 520)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(30)
}

// MARK: - 记忆详情

private struct MemoryWorkspaceDetailView: View {
    let workspace: MemoryWorkspaceRecord
    let selectedRequest: CapturedFixedInput?
    @State private var includeArchived = false

    private var visibleFacts: [MemoryFactRecord] {
        includeArchived ? workspace.facts : workspace.facts.filter(\.isActive)
    }

    private var injectedIntoSelectedRequest: Bool {
        selectedRequest?.cwd == workspace.path && selectedRequest?.memoryProfile != nil
    }

    package var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workspace.title).font(.title3).bold()
                        Text(workspace.path)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    if injectedIntoSelectedRequest {
                        Label("已注入所选请求", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                GroupBox(label: Label("自动注入 Profile · \(workspace.profile.entries.count) 条", systemImage: "brain")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if workspace.profile.entries.isEmpty {
                            Text("当前 Profile 为空，不会向 System Prompt 注入 memory-profile。")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(workspace.profile.entries.enumerated()), id: \.offset) { index, entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(entry).textSelection(.enabled)
                                }
                            }
                        }
                        if let updated = workspace.profile.updatedAt {
                            Text("更新时间：\(updated.formatted(date: .abbreviated, time: .standard))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                HStack {
                    Label("长期 Facts · \(workspace.facts.filter(\.isActive).count) 条活跃", systemImage: "tray.full")
                        .font(.headline)
                    Spacer()
                    Toggle("包含已归档", isOn: $includeArchived)
                        .toggleStyle(.switch)
                }

                if visibleFacts.isEmpty {
                    Text("没有可显示的 Fact。")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ForEach(visibleFacts) { fact in memoryFactCard(fact) }
                }

                Label("此页面只读。记忆修改和遗忘仍应通过 memory_remember / memory_edit / memory_forget，并保留人工审批。", systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
            .padding(16)
        }
    }

    private func memoryFactCard(_ fact: MemoryFactRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(fact.kind.uppercased())
                    .font(.caption2.bold())
                    .foregroundColor(kindColor(fact.kind))
                if !fact.isActive {
                    Text("已归档").font(.caption2).foregroundColor(.orange)
                }
                Spacer()
                Text(fact.id).font(.caption2.monospaced()).foregroundColor(.secondary).textSelection(.enabled)
            }
            Text(fact.text).textSelection(.enabled)
            if !fact.tags.isEmpty {
                Text(fact.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 12) {
                Text("来源：\(fact.sessionId)#\(fact.sequence)")
                if let updated = fact.updatedAt ?? fact.createdAt {
                    Text(updated.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .textSelection(.enabled)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.18)))
    }

    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "preference": return .purple
        case "decision": return .blue
        case "convention": return .orange
        default: return .secondary
        }
    }
}

private func copyToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}
