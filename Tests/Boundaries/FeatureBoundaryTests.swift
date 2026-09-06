import Foundation
import Testing
import DSHCore
import DSHUI
import LocalModelFeature
@testable import ArchiveFeature
@testable import InspectorFeature
@testable import PluginsFeature

struct FeatureBoundaryTests {
    @Test
    func testLocalModelUsesItsOwnSettingsDomainAndState() throws {
        let name = "dsh-feature-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("/missing/test-dsh", forKey: "dshPath")
        defaults.set("Existing model", forKey: "localModelName")
        defaults.set("--port 8000", forKey: "localModelStartArguments")
        defaults.set(false, forKey: "stopLocalModelOnQuit")
        let runtime = DSHService(defaults: defaults, monitor: false)
        let model = LocalModelService(defaults: defaults, monitor: false)
        #expect(model.localModelName == "Existing model")
        #expect(model.localModelStartArguments == "--port 8000")
        #expect(!(model.stopLocalModelOnQuit))
        defaults.set(3199, forKey: "port")
        model.localModelName = "Renamed model"
        model.persist()
        #expect(defaults.integer(forKey: "port") == 3199)
        model.localModelStartExecutable = "/missing/model-server"
        model.startLocalModel()
        guard case .failed = model.localModelState else { Issue.record("invalid model executable must fail"); return }
        #expect(runtime.state == .stopped)
        #expect(!(runtime.isMaintaining))
    }

    @Test
    func testObserversOwnSeparateResourcesAndCaches() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-observers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let module = directory.appendingPathComponent("inventory's module.mjs")
        try Data("export const name = 'test'".utf8).write(to: module)
        let pluginOutput = directory.appendingPathComponent("plugin-inventory.json")
        let inspectorOutput = directory.appendingPathComponent("request-inspector.json")
        try Data("plugin".utf8).write(to: pluginOutput)
        try Data("inspector".utf8).write(to: inspectorOutput)

        let observer = PluginLaunchObserver(moduleURL: module, outputURL: pluginOutput)
        let prepared = observer.prepare()
        #expect(prepared.arguments.first == "--patch")
        #expect(prepared.arguments.count == 2)
        let patch = try String(contentsOfFile: prepared.arguments[1], encoding: .utf8)
        #expect(patch.contains("inventory''s module.mjs"))
        #expect(FileManager.default.fileExists(atPath: inspectorOutput.path))
        #expect(!(FileManager.default.fileExists(atPath: pluginOutput.path)))

        let name = "dsh-observer-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = InspectorPreferences(defaults: defaults)
        preferences.captureModelRequests = false
        let inspector = InspectorLaunchObserver(preferences: preferences, moduleURL: module, outputURL: inspectorOutput)
        #expect(inspector.prepare().arguments.isEmpty)
        preferences.captureModelRequests = true
        #expect(inspector.prepare().arguments.first == "--patch")
    }

    @Test
    func testArchiveRestorePreservesUnrelatedUpstreamData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-archive-\(UUID().uuidString)")
        let storage = root.appendingPathComponent("storages")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = storage.appendingPathComponent("workspace.json")
        let initial = #"{"global":{"archivedSessionIds":["chosen","other"],"futureField":"keep"},"tables":{"untouched":{"value":7}}}"#
        try Data(initial.utf8).write(to: url)
        let backup = try ArchiveRepository.restore(ids: ["chosen"], root: root)
        let result = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let global = try #require(result["global"] as? [String: Any])
        #expect(global["archivedSessionIds"] as? [String] == ["other"])
        #expect(global["futureField"] as? String == "keep")
        #expect(result["tables"] != nil)
        #expect(FileManager.default.fileExists(atPath: backup.path))
    }

    @Test
    func testBundledThemesRemainValidAfterMovingSources() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Themes")
        let themes = ThemePresetCatalog.loadBundledPresets(from: root)
        #expect(themes.count == 11)
        #expect(Set(themes.map(\.id)).count == 11)
    }

    @Test @MainActor
    func testArchiveMaintenanceIsReleasedAfterFailureAndSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-archive-store-\(UUID().uuidString)")
        let name = "dsh-archive-store-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set("/missing/test-dsh", forKey: "dshPath")
        let runtime = DSHService(defaults: defaults, monitor: false)
        runtime.port = 0 // No real service port is inspected or started by this fixture.
        let store = ArchiveStore(runtime: runtime, dataRootURL: root)
        let conversation = ArchivedConversation(id: "chosen", title: "Test", workspaceTitle: nil,
            cwd: nil, createdAt: nil, updatedAt: nil, byteCount: 0, directoryURL: nil)
        store.restore(conversation)
        #expect(runtime.isMaintaining)
        runtime.start()
        #expect(runtime.state == .stopped)
        for _ in 0..<100 where store.isBusy { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(!store.isBusy)
        #expect(!runtime.isMaintaining)
        #expect(store.errorMessage != nil)

        let storage = root.appendingPathComponent("storages")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try Data(#"{"global":{"archivedSessionIds":["chosen"]}}"#.utf8)
            .write(to: storage.appendingPathComponent("workspace.json"))
        store.restore(conversation)
        for _ in 0..<100 where store.isBusy { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(!runtime.isMaintaining)
        #expect(store.errorMessage == nil)
        #expect(store.statusMessage != nil)
        #expect(store.items.isEmpty)

        let token = try #require(runtime.beginMaintenance())
        store.restore(conversation)
        #expect(!store.isBusy)
        #expect(runtime.isMaintaining)
        runtime.endMaintenance(token)
    }

    @Test
    func testPluginDecisionsUseTypedStates() {
        #expect(PluginRuntimeStatus.active.isComplete)
        #expect(PluginRuntimeStatus.disabled.isComplete)
        #expect(!(PluginRuntimeStatus.partial.isComplete))
        #expect(PluginRuntimeStatus.partial.isSettled)
        #expect(!(PluginRuntimeStatus.pending.isSettled))
        #expect(!(PluginRuntimeStatus.notFound.isComplete))
        #expect(!(PluginRuntimeStatus.failed.isComplete))
    }
}
