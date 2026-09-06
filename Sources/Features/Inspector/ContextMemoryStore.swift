import Foundation
import Combine
import DSHCore

final class ContextMemoryStore: ObservableObject {
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

func fileModificationDate(_ url: URL) -> Date? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
    return attributes[.modificationDate] as? Date
}
