import Foundation
import Testing
import DSHCore
@testable import PluginsFeature

struct PluginSupportTests {
    @Test
    func testInventoryAndOfflineRecovery() async throws {
        #expect(PluginVersions.isNewer("0.2.10", than: "0.2.9"))
        #expect(!PluginVersions.isNewer("0.2.0", than: "0.3.0-beta.1"))
        #expect(PluginVersions.isNewer("0.3.0", than: "0.3.0-beta.1"))
        #expect(PluginVersions.isNewer("0.3.0-rc.10", than: "0.3.0-rc.9"))
        #expect(!PluginVersions.isNewer("0.3.0+new", than: "0.3.0+old"))
        #expect(!PluginVersions.isNewer("0.3.0", than: "unknown"))
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("dsh-plugin-tests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let profile = root.appendingPathComponent("profiles/web")
        let backups = root.appendingPathComponent("backups")
        try fm.createDirectory(at: profile.appendingPathComponent("node_modules/example"), withIntermediateDirectories: true)
        func write(_ path: String, _ text: String) throws {
            try Data(text.utf8).write(to: profile.appendingPathComponent(path), options: .atomic)
        }
        try write("package.json", #"{"dependencies":{"example":"0.2.0","local-plugin":"link:../local","@deepseek-ai/dsh-base":"1.0.0"}}"#)
        try write("node_modules/example/package.json", #"{"name":"example","version":"0.2.0"}"#)
        try write("node_modules/example/index.js", "original plugin bytes")
        try write("pnpm-lock.yaml", "original lock")
        try write("cordis.patch.yml", "original config")
        try fm.createSymbolicLink(atPath: profile.appendingPathComponent("node_modules/example-link").path, withDestinationPath: "example")
        let plugins = try PluginFiles.load(profile: profile)
        #expect(plugins.count == 2, "built-in bundles must not be offered for independent updates")
        #expect(plugins[0].installedVersion == "0.2.0")
        #expect(plugins[0].registryManaged)
        #expect(!plugins[1].registryManaged)
        #expect(!PluginFiles.validName("../escape"))
        #expect(!PluginFiles.validName("--global"))
        #expect(PluginFiles.validName("@scope/plugin-name"))

        let backup = try PluginFiles.backup(profile: profile, root: backups, reason: "test update")
        #expect(PluginFiles.backups(root: backups, profile: profile).count == 1)
        #expect(PluginFiles.backups(root: backups, profile: root.appendingPathComponent("another")).isEmpty)
        try write("package.json", #"{"dependencies":{"example":"1.0.0"}}"#)
        try write("node_modules/example/index.js", "new plugin bytes")
        try write("pnpm-lock.yaml", "changed lock")
        try write("cordis.patch.yml", "changed config")
        try write("new-install-file", "partial install")
        let beforeRestore = try PluginFiles.backup(profile: profile, root: backups, reason: "before restore")
        try PluginFiles.restore(backup, profile: profile, root: backups)
        #expect(tryString(profile.appendingPathComponent("node_modules/example/index.js")) == "original plugin bytes")
        #expect(tryString(profile.appendingPathComponent("pnpm-lock.yaml")) == "original lock")
        #expect(tryString(profile.appendingPathComponent("cordis.patch.yml")) == "original config")
        #expect(!fm.fileExists(atPath: profile.appendingPathComponent("new-install-file").path))
        #expect(tryString(profile.appendingPathComponent("node_modules/example-link/index.js")) == "original plugin bytes")
        try PluginFiles.restore(beforeRestore, profile: profile, root: backups)
        #expect(tryString(profile.appendingPathComponent("node_modules/example/index.js")) == "new plugin bytes")
        try fm.removeItem(at: profile.appendingPathComponent("package.json"))
        _ = try PluginFiles.backup(profile: profile, root: backups, reason: "preserve incomplete install", allowIncomplete: true)
        try PluginFiles.restore(backup, profile: profile, root: backups)
        let recovered = try PluginFiles.load(profile: profile)
        #expect(recovered.first?.installedVersion == "0.2.0")

        do {
            let lock = try PluginProfileLock(profile: profile)
            do {
                _ = try PluginProfileLock(profile: profile)
                Issue.record("concurrent mutation lock was incorrectly acquired")
            } catch {}
            withExtendedLifetime(lock) {}
        }
        _ = try PluginProfileLock(profile: profile)

        let snapshot = try JSONDecoder().decode(PluginInventorySnapshot.self, from: Data(#"{"pid":123,"updatedAt":1,"entries":[{"moduleName":"example/tool","enabled":true,"fiberPhase":"active"},{"moduleName":"bad","enabled":true,"fiberPhase":"failed"},{"moduleName":"off","enabled":false,"fiberPhase":null},{"moduleName":"waiting","enabled":true,"fiberPhase":"pending"}]}"#.utf8))
        #expect(snapshot.status(for: "example") == .active)
        #expect(snapshot.status(for: "bad") == .failed)
        #expect(snapshot.status(for: "off") == .disabled)
        #expect(snapshot.status(for: "waiting") == .pending)
        #expect(snapshot.status(for: "missing") == .notFound)
        let partial = PluginInventorySnapshot(pid: 1, updatedAt: 0, entries: [
            .init(moduleName: "example", enabled: true, fiberPhase: "active"),
            .init(moduleName: "example/optional", enabled: true, fiberPhase: "pending")
        ])
        #expect(partial.status(for: "example") == .partial)

        let argument = "literal $(touch should-not-exist); `whoami`"
        let result = try await ProcessCommand.run(executable: "/usr/bin/printf", arguments: ["%s", argument], directory: profile, environment: [:])
        #expect(result.status == 0 && result.output == argument)
        #expect(!fm.fileExists(atPath: profile.appendingPathComponent("should-not-exist").path))
        let failure = try await ProcessCommand.run(executable: "/bin/sh", arguments: ["-c", "printf failure >&2; exit 17"], directory: profile, environment: [:])
        #expect(failure.status == 17 && failure.output == "failure")
        let verbose = try await ProcessCommand.run(executable: "/bin/sh", arguments: ["-c", "head -c 300000 /dev/zero; printf end"], directory: profile, environment: ["PATH": "/usr/bin:/bin"])
        #expect(verbose.status == 0 && verbose.output.hasSuffix("end") && verbose.output.utf8.count == 262_144)
        let start = Date()
        do {
            _ = try await ProcessCommand.run(executable: "/bin/sh", arguments: ["-c", "sleep 30 & wait"], directory: profile, environment: ["PATH": "/bin"], timeout: 0.2)
            Issue.record("timeout failed")
        } catch {
            #expect(error.localizedDescription.contains("超时"))
            #expect(Date().timeIntervalSince(start) < 5, "child processes must be terminated with their parent")
        }
        print("PluginSupport tests passed: inventory, sources, offline rollback, locks, argv, exit status, verbose output, timeout.")
    }

    private func tryString(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
}
