import Foundation

struct ArchivedConversation: Identifiable, Hashable {
    let id: String // 对话唯一id
    let title: String // 对话标题
    let workspaceTitle: String? // 所属工作区名称（按项目分类的项目概念）
    let cwd: String? // 对话当时所在的项目目录
    let createdAt: Date?  // 创建时间
    let updatedAt: Date? // 更新时间
    let byteCount: Int64 // 对话日志占用的字节数
    let directoryURL: URL? //对话日志目录，找不到为nil
}

// 读档时内部辅助数据，私有
struct ArchiveWorkspaceInfo {
    let title: String // 工作区名称
    let path: String // 工作区路径
}

// 一次归档扫描完整结果，私有
struct ArchiveSnapshot {
    let items: [ArchivedConversation] // 扫描到的所有归档对话
    let totalByteCount: Int64 // 所有归档日志大小
}

// 错误类型
enum ArchiveManagerError: LocalizedError {
    case message(String) // 错误消息

    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}
