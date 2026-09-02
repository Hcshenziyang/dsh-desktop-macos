import Foundation
import SwiftUI
import AppKit
import Combine

// MARK: - 模型固定输入

private struct PromptSectionRecord: Identifiable, Hashable {
    let id: String
    let name: String
    let text: String
}

private struct ToolCatalogEntry: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let description: String
    let rawJSON: String
}

private struct SkillCatalogEntry: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let description: String
}

private struct FixedInstructionRecord: Identifiable, Hashable {
    let id: String
    let title: String
    let source: String
    let text: String
    let sourceJSON: String
}

private struct CapturedFixedInput: Identifiable, Hashable {
    let id: String
    let capturedAt: Date
    let sessionId: String
    let ordinal: Int
    let turn: Int?
    let step: Int?
    let attempt: Int
    let cwd: String?
    let provider: String
    let model: String
    let reasoningEffort: String?
    let systemPrompt: String
    let promptSections: [PromptSectionRecord]
    let promptSectionsMatchFinal: Bool
    let tools: [ToolCatalogEntry]
    let skills: [SkillCatalogEntry]
    let skillCatalogText: String
    let fixedInstructions: [FixedInstructionRecord]

    var positionTitle: String {
        if let turn, let step {
            let retry = attempt > 1 ? " · 尝试 \(attempt)" : ""
            return "第 \(turn) 轮 · 第 \(step) 步\(retry)"
        }
        return "模型请求 #\(ordinal)"
    }

    var routeTitle: String { "\(provider) / \(model)" }

    var memoryProfile: String? {
        extractMemoryProfile(from: systemPrompt)
    }
}

// MARK: - 长期记忆数据

private struct MemoryProfileRecord: Hashable {
    let entries: [String]
    let updatedAt: Date?
}

private struct MemoryFactRecord: Identifiable, Hashable {
    let id: String
    let workspacePath: String
    let kind: String
    let text: String
    let tags: [String]
    let sessionId: String
    let sequence: Int
    let createdAt: Date?
    let updatedAt: Date?
    let state: String

    var isActive: Bool { state == "active" }
}

private struct MemoryWorkspaceRecord: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let profile: MemoryProfileRecord
    let facts: [MemoryFactRecord]

    var title: String {
        let value = URL(fileURLWithPath: path).lastPathComponent
        return value.isEmpty ? path : value
    }
}

// MARK: - 数据读取

private enum ContextMemoryReadError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}

private func jsonObject(at url: URL) throws -> [String: Any] {
    do {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ContextMemoryReadError.message("\(url.lastPathComponent) 不是 JSON 对象")
        }
        return object
    } catch let error as ContextMemoryReadError {
        throw error
    } catch {
        throw ContextMemoryReadError.message("无法读取 \(url.path)：\(error.localizedDescription)")
    }
}

private func prettyJSON(_ value: Any) -> String {
    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(
        withJSONObject: value,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
       ), let string = String(data: data, encoding: .utf8) {
        return string
    }
    if let string = value as? String { return string }
    return String(describing: value)
}

private func integer(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    if let value = value as? Int { return value }
    return nil
}

private func dateFromEpochMilliseconds(_ value: Any?) -> Date? {
    guard let number = value as? NSNumber else { return nil }
    let milliseconds = number.doubleValue
    guard milliseconds.isFinite, milliseconds > 0 else { return nil }
    return Date(timeIntervalSince1970: milliseconds / 1000)
}

private func extractMemoryProfile(from systemPrompt: String) -> String? {
    guard let start = systemPrompt.range(of: "<memory-profile>"),
          let end = systemPrompt.range(of: "</memory-profile>", range: start.upperBound..<systemPrompt.endIndex) else {
        return nil
    }
    return String(systemPrompt[start.lowerBound..<end.upperBound])
}

private func textFromContentBlocks(_ content: Any?) -> String {
    guard let blocks = content as? [[String: Any]] else {
        if let string = content as? String { return string }
        return content == nil ? "" : prettyJSON(content as Any)
    }
    return blocks.compactMap { block -> String? in
        switch block["type"] as? String {
        case "text", "reasoning": return block["text"] as? String
        case "tool-call":
            let name = block["name"] as? String ?? "unknown"
            return "[工具 \(name)]\n\(block["arguments"] as? String ?? "")"
        case "tool-result": return textFromContentBlocks(block["content"])
        case "image": return "[图片]"
        default: return prettyJSON(block)
        }
    }.joined(separator: "\n\n")
}

private func isFixedInstructionMessage(_ message: [String: Any]) -> Bool {
    if message["role"] as? String == "system" { return true }
    guard let source = message["source"] as? [String: Any],
          let kind = source["kind"] as? String else { return false }
    if kind == "agent-instructions" || kind == "skill-invocation" { return true }
    return kind == "plugin" && source["plugin"] as? String == "agent-instructions"
}

private func instructionLabels(_ source: [String: Any], role: String) -> (title: String, source: String) {
    let kind = source["kind"] as? String ?? role
    switch kind {
    case "agent-instructions":
        return ("工作区指令（AGENTS.md）", "agent-instructions")
    case "skill-invocation":
        let name = source["name"] as? String ?? "unknown"
        return ("已加载 Skill：\(name)", "skill-invocation · \(name)")
    case "plugin":
        let plugin = source["plugin"] as? String ?? "unknown"
        return (plugin == "agent-instructions" ? "工作区基础指令（AGENTS.md）" : "插件固定指令", "plugin · \(plugin)")
    default:
        return (role == "system" ? "附加 System 消息" : "固定指令", kind)
    }
}

private func latestSkillCatalog(in messages: [[String: Any]]) -> [String: Any]? {
    messages.reversed().first {
        ($0["source"] as? [String: Any])?["kind"] as? String == "skill-catalog"
    }
}

private func parseCapturedRequests(at url: URL) throws -> [CapturedFixedInput] {
    let root = try jsonObject(at: url)
    guard let rows = root["requests"] as? [[String: Any]] else {
        throw ContextMemoryReadError.message("模型固定输入缓存中缺少 requests 数组")
    }

    return rows.compactMap { row -> CapturedFixedInput? in
        guard let id = row["id"] as? String,
              let sessionId = row["sessionId"] as? String,
              let capturedAt = dateFromEpochMilliseconds(row["capturedAt"]) else { return nil }

        // 兼容第一版缓存：旧版把字段放在 request 中；新版只保留固定输入。
        let legacyRequest = row["request"] as? [String: Any]
        let route = row["route"] as? [String: Any] ?? legacyRequest ?? [:]
        let systemPrompt = row["system"] as? String ?? legacyRequest?["system"] as? String ?? ""

        let rawTools = row["tools"] as? [[String: Any]]
            ?? legacyRequest?["tools"] as? [[String: Any]]
            ?? []
        let tools = rawTools.enumerated().map { index, tool in
            ToolCatalogEntry(
                name: tool["name"] as? String ?? "tool-\(index)",
                description: tool["description"] as? String ?? "",
                rawJSON: prettyJSON(tool)
            )
        }

        let assembly = row["promptAssembly"] as? [String: Any]
        var promptSections = (assembly?["sections"] as? [[String: Any]] ?? []).enumerated().compactMap {
            index, section -> PromptSectionRecord? in
            guard let text = section["text"] as? String, !text.isEmpty else { return nil }
            let name = section["name"] as? String ?? "section-\(index + 1)"
            return PromptSectionRecord(id: "\(index)-\(name)", name: name, text: text)
        }
        if promptSections.isEmpty, !systemPrompt.isEmpty {
            promptSections = [PromptSectionRecord(id: "final-system", name: "最终 System Prompt", text: systemPrompt)]
        }
        let assembledText = promptSections.map(\.text).joined(separator: "\n\n")
        let sectionsMatchFinal = assembly?["matchesFinal"] as? Bool ?? (assembledText == systemPrompt)

        let legacyMessages = legacyRequest?["messages"] as? [[String: Any]] ?? []
        let catalog = row["skillCatalog"] as? [String: Any] ?? latestSkillCatalog(in: legacyMessages)
        let catalogSource = catalog?["source"] as? [String: Any] ?? [:]
        let skills = (catalogSource["entries"] as? [[String: Any]] ?? []).compactMap { entry -> SkillCatalogEntry? in
            guard let name = entry["name"] as? String else { return nil }
            return SkillCatalogEntry(name: name, description: entry["description"] as? String ?? "")
        }
        let skillCatalogText = textFromContentBlocks(catalog?["content"])

        let rawInstructions: [[String: Any]]
        if let captured = row["fixedInstructions"] as? [[String: Any]] {
            rawInstructions = captured
        } else {
            rawInstructions = legacyMessages.filter(isFixedInstructionMessage)
        }
        let fixedInstructions = rawInstructions.enumerated().compactMap { index, message -> FixedInstructionRecord? in
            let text = textFromContentBlocks(message["content"])
            guard !text.isEmpty else { return nil }
            let role = message["role"] as? String ?? "user"
            let source = message["source"] as? [String: Any] ?? [:]
            let labels = instructionLabels(source, role: role)
            return FixedInstructionRecord(
                id: message["id"] as? String ?? "instruction-\(index)",
                title: labels.title,
                source: labels.source,
                text: text,
                sourceJSON: prettyJSON(source)
            )
        }

        return CapturedFixedInput(
            id: id,
            capturedAt: capturedAt,
            sessionId: sessionId,
            ordinal: integer(row["ordinal"]) ?? 0,
            turn: integer(row["turn"]),
            step: integer(row["step"]),
            attempt: integer(row["attempt"]) ?? 1,
            cwd: row["cwd"] as? String,
            provider: route["provider"] as? String ?? "unknown",
            model: route["model"] as? String ?? "unknown",
            reasoningEffort: route["reasoningEffort"] as? String,
            systemPrompt: systemPrompt,
            promptSections: promptSections,
            promptSectionsMatchFinal: sectionsMatchFinal,
            tools: tools,
            skills: skills,
            skillCatalogText: skillCatalogText,
            fixedInstructions: fixedInstructions
        )
    }.sorted { $0.capturedAt > $1.capturedAt }
}

private func memoryPluginIsInstalled(root: URL) -> Bool {
    let candidates = [
        root.appendingPathComponent("profiles/web/node_modules/dsh-native-memory/package.json"),
        root.appendingPathComponent("profiles/node_modules/dsh-native-memory/package.json"),
    ]
    return candidates.contains { FileManager.default.fileExists(atPath: $0.path) }
}

private func parseMemoryWorkspaces(at url: URL) throws -> [MemoryWorkspaceRecord] {
    let root = try jsonObject(at: url)
    guard let tables = root["tables"] as? [String: Any] else {
        throw ContextMemoryReadError.message("dsh_memory.json 中缺少 tables")
    }
    let factRows = tables["facts"] as? [String: Any] ?? [:]
    let profileRows = tables["profiles"] as? [String: Any] ?? [:]
    var factsByWorkspace: [String: [MemoryFactRecord]] = [:]
    var profilesByWorkspace: [String: MemoryProfileRecord] = [:]

    for raw in factRows.values {
        guard let fact = raw as? [String: Any],
              let id = fact["id"] as? String,
              let workspacePath = fact["workspacePath"] as? String,
              let text = fact["text"] as? String else { continue }
        factsByWorkspace[workspacePath, default: []].append(MemoryFactRecord(
            id: id,
            workspacePath: workspacePath,
            kind: fact["kind"] as? String ?? "fact",
            text: text,
            tags: fact["tags"] as? [String] ?? [],
            sessionId: fact["sessionId"] as? String ?? "unknown",
            sequence: integer(fact["seq"]) ?? 0,
            createdAt: dateFromEpochMilliseconds(fact["createdAt"]),
            updatedAt: dateFromEpochMilliseconds(fact["updatedAt"]),
            state: fact["state"] as? String ?? "active"
        ))
    }

    for raw in profileRows.values {
        guard let profile = raw as? [String: Any],
              let workspacePath = profile["workspacePath"] as? String else { continue }
        profilesByWorkspace[workspacePath] = MemoryProfileRecord(
            entries: profile["entries"] as? [String] ?? [],
            updatedAt: dateFromEpochMilliseconds(profile["updatedAt"])
        )
    }

    let paths = Set(factsByWorkspace.keys).union(profilesByWorkspace.keys)
    return paths.map { path in
        let facts = (factsByWorkspace[path] ?? []).sorted {
            ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast)
        }
        return MemoryWorkspaceRecord(
            path: path,
            profile: profilesByWorkspace[path] ?? MemoryProfileRecord(entries: [], updatedAt: nil),
            facts: facts
        )
    }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
}

private final class ContextMemoryStore: ObservableObject {
    @Published private(set) var requests: [CapturedFixedInput] = []
    @Published private(set) var memoryWorkspaces: [MemoryWorkspaceRecord] = []
    @Published private(set) var memoryPluginInstalled = false
    @Published private(set) var issues: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastLoadedAt: Date?

    private var inspectorModificationDate: Date?
    private var memoryModificationDate: Date?

    let inspectorURL = requestInspectorOutputURL()
    let memoryURL = dshHomeDirectoryURL().appendingPathComponent("storages/dsh_memory.json")

    func reload() {
        guard !isLoading else { return }
        isLoading = true
        let inspectorURL = inspectorURL
        let memoryURL = memoryURL
        let dshRoot = dshHomeDirectoryURL()
        let previousRequests = requests
        let previousMemories = memoryWorkspaces
        let previousInspectorDate = inspectorModificationDate
        let previousMemoryDate = memoryModificationDate
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var issues: [String] = []
            let inspectorExists = FileManager.default.fileExists(atPath: inspectorURL.path)
            let memoryExists = FileManager.default.fileExists(atPath: memoryURL.path)
            let inspectorDate = fileModificationDate(inspectorURL)
            let memoryDate = fileModificationDate(memoryURL)

            let requests: [CapturedFixedInput]
            if inspectorExists, previousInspectorDate == nil || inspectorDate != previousInspectorDate {
                do { requests = try parseCapturedRequests(at: inspectorURL) }
                catch { requests = []; issues.append(error.localizedDescription) }
            } else {
                requests = inspectorExists ? previousRequests : []
            }

            let memories: [MemoryWorkspaceRecord]
            if memoryExists, previousMemoryDate == nil || memoryDate != previousMemoryDate {
                do { memories = try parseMemoryWorkspaces(at: memoryURL) }
                catch { memories = []; issues.append(error.localizedDescription) }
            } else {
                memories = memoryExists ? previousMemories : []
            }

            let installed = memoryPluginIsInstalled(root: dshRoot)
            DispatchQueue.main.async {
                guard let self else { return }
                self.requests = requests
                self.memoryWorkspaces = memories
                self.memoryPluginInstalled = installed
                self.issues = issues
                self.inspectorModificationDate = inspectorExists ? inspectorDate : nil
                self.memoryModificationDate = memoryExists ? memoryDate : nil
                self.isLoading = false
                self.lastLoadedAt = Date()
            }
        }
    }
}

private func fileModificationDate(_ url: URL) -> Date? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
    return attributes[.modificationDate] as? Date
}

// MARK: - 主窗口

struct ContextMemoryView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case fixedInput = "模型固定输入"
        case memory = "长期记忆"
        var id: String { rawValue }
    }

    @StateObject private var store = ContextMemoryStore()
    @ObservedObject private var mgr = Manager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .fixedInput
    @State private var selectedRequestId: String?
    @State private var selectedWorkspacePath: String?
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
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
            Image(systemName: mgr.captureModelRequests ? "doc.text.magnifyingglass" : "eye.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(fixedInputEmptyTitle).font(.headline)
            Text(fixedInputEmptyDescription)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 600)
            if !mgr.captureModelRequests {
                Button("在设置中启用") { mgr.captureModelRequests = true; mgr.persist() }
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
        if !mgr.captureModelRequests { return "模型固定输入捕获已关闭" }
        if case .externalRunning = mgr.state { return "当前外部 DSH 没有挂载检查器" }
        if mgr.state.webReady { return "等待下一次模型请求" }
        return "启动 DSH 后开始捕获"
    }

    private var fixedInputEmptyDescription: String {
        if !mgr.captureModelRequests { return "启用后重启 DSH。检查器只观察固定输入，不修改提示词或模型响应。" }
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

    var body: some View {
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

    var body: some View {
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
