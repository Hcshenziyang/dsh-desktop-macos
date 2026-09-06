import Foundation
import Combine
import DSHCore

final class ArchiveStore: ObservableObject {
    @Published private(set) var items: [ArchivedConversation] = []
    @Published private(set) var totalByteCount: Int64 = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    let dataRootURL: URL
    private let runtime: DSHService

    init(runtime: DSHService, dataRootURL: URL = dshHomeDirectoryURL()) {
        self.runtime = runtime
        self.dataRootURL = dataRootURL
    }

    // 路径拼接优化显示
    var displayDataRoot: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = dataRootURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }
        return path
    }

    //
    func reload() {
        guard !isLoading, !isBusy else { return }
        isLoading = true
        errorMessage = nil
        let root = dataRootURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let snapshot = try ArchiveRepository.loadSnapshot(root: root)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.items = snapshot.items
                    self.totalByteCount = snapshot.totalByteCount
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.items = []
                    self.totalByteCount = 0
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func restore(_ conversation: ArchivedConversation) {
        perform {
            let backup = try ArchiveRepository.restore(ids: [conversation.id], root: self.dataRootURL)
            return "已恢复“\(conversation.title)”；索引备份：\(ArchiveRepository.abbreviatedPath(backup.path))"
        }
    }

    func delete(_ conversation: ArchivedConversation) {
        perform {
            let result = try ArchiveRepository.delete(ids: [conversation.id], root: self.dataRootURL)
            return "已将“\(conversation.title)”移到废纸篓；索引备份：\(ArchiveRepository.abbreviatedPath(result.backup.path))"
        }
    }

    func deleteAll() {
        let ids = items.map(\.id)
        guard !ids.isEmpty else { return }
        perform {
            let result = try ArchiveRepository.delete(ids: ids, root: self.dataRootURL)
            return "已清理 \(ids.count) 条归档会话（\(result.trashedCount) 个日志目录已移到废纸篓）；索引备份：\(ArchiveRepository.abbreviatedPath(result.backup.path))"
        }
    }

    private func perform(operation: @escaping () throws -> String) {
        guard !isBusy else { return }
        guard !runtime.ownsProcess, !runtime.state.portActive else {
            errorMessage = "请先停止 DSH 服务，避免运行中的进程覆盖会话索引。"
            return
        }
        guard let token = runtime.beginMaintenance() else {
            errorMessage = "DSH 正在维护，请稍后重试。"
            return
        }
        let runtime = runtime
        let servicePort = runtime.port
        isBusy = true
        statusMessage = nil
        errorMessage = nil
        let root = dataRootURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard listeningPid(port: servicePort) == nil else {
                    throw ArchiveManagerError.message("DSH 服务仍在监听端口 \(servicePort)。请先停止服务，避免运行中的进程覆盖会话索引。")
                }
                let message = try operation()
                let snapshot = try ArchiveRepository.loadSnapshot(root: root)
                DispatchQueue.main.async {
                    defer { runtime.endMaintenance(token) }
                    guard let self else { return }
                    self.items = snapshot.items
                    self.totalByteCount = snapshot.totalByteCount
                    self.isBusy = false
                    self.statusMessage = message
                }
            } catch {
                DispatchQueue.main.async {
                    defer { runtime.endMaintenance(token) }
                    guard let self else { return }
                    self.isBusy = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
