import Foundation
import DSHCore

// MARK: - 数据读取

private enum ContextMemoryReadError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}

func jsonObject(at url: URL) throws -> [String: Any] {
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

func prettyJSON(_ value: Any) -> String {
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

func integer(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    if let value = value as? Int { return value }
    return nil
}

func dateFromEpochMilliseconds(_ value: Any?) -> Date? {
    guard let number = value as? NSNumber else { return nil }
    let milliseconds = number.doubleValue
    guard milliseconds.isFinite, milliseconds > 0 else { return nil }
    return Date(timeIntervalSince1970: milliseconds / 1000)
}

func extractMemoryProfile(from systemPrompt: String) -> String? {
    guard let start = systemPrompt.range(of: "<memory-profile>"),
          let end = systemPrompt.range(of: "</memory-profile>", range: start.upperBound..<systemPrompt.endIndex) else {
        return nil
    }
    return String(systemPrompt[start.lowerBound..<end.upperBound])
}

func textFromContentBlocks(_ content: Any?) -> String {
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

func isFixedInstructionMessage(_ message: [String: Any]) -> Bool {
    if message["role"] as? String == "system" { return true }
    guard let source = message["source"] as? [String: Any],
          let kind = source["kind"] as? String else { return false }
    if kind == "agent-instructions" || kind == "skill-invocation" { return true }
    return kind == "plugin" && source["plugin"] as? String == "agent-instructions"
}

func instructionLabels(_ source: [String: Any], role: String) -> (title: String, source: String) {
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

func latestSkillCatalog(in messages: [[String: Any]]) -> [String: Any]? {
    messages.reversed().first {
        ($0["source"] as? [String: Any])?["kind"] as? String == "skill-catalog"
    }
}

func parseCapturedRequests(at url: URL) throws -> [CapturedFixedInput] {
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

func memoryPluginIsInstalled(root: URL) -> Bool {
    let candidates = [
        root.appendingPathComponent("profiles/web/node_modules/dsh-native-memory/package.json"),
        root.appendingPathComponent("profiles/node_modules/dsh-native-memory/package.json"),
    ]
    return candidates.contains { FileManager.default.fileExists(atPath: $0.path) }
}

func parseMemoryWorkspaces(at url: URL) throws -> [MemoryWorkspaceRecord] {
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
