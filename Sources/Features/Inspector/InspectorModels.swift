import Foundation

struct PromptSectionRecord: Identifiable, Hashable {
    let id: String
    let name: String
    let text: String
}

struct ToolCatalogEntry: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let description: String
    let rawJSON: String
}

struct SkillCatalogEntry: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let description: String
}

struct FixedInstructionRecord: Identifiable, Hashable {
    let id: String
    let title: String
    let source: String
    let text: String
    let sourceJSON: String
}

struct CapturedFixedInput: Identifiable, Hashable {
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

struct MemoryProfileRecord: Hashable {
    let entries: [String]
    let updatedAt: Date?
}

struct MemoryFactRecord: Identifiable, Hashable {
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

struct MemoryWorkspaceRecord: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let profile: MemoryProfileRecord
    let facts: [MemoryFactRecord]

    var title: String {
        let value = URL(fileURLWithPath: path).lastPathComponent
        return value.isEmpty ? path : value
    }
}
