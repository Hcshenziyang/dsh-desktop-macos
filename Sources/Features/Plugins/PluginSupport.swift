import Foundation
import Darwin

struct ManagedPlugin: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let requirement: String
    let installedVersion: String?
    let registryManaged: Bool
}

struct PluginBackup: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let reason: String
    let profilePath: String
}

enum PluginRuntimeStatus: Equatable {
    case notFound, disabled, failed, active, partial, pending

    var isComplete: Bool { self == .active || self == .disabled }
    var isSettled: Bool { isComplete || self == .partial }
}

struct PluginInventorySnapshot: Decodable {
    struct Entry: Decodable {
        let moduleName: String
        let enabled: Bool
        let fiberPhase: String?
    }
    let pid: Int32
    let updatedAt: Double
    let entries: [Entry]

    func status(for package: String) -> PluginRuntimeStatus {
        let matches = entries.filter { $0.moduleName == package || $0.moduleName.hasPrefix(package + "/") }
        guard !matches.isEmpty else { return .notFound }
        let enabled = matches.filter(\.enabled)
        guard !enabled.isEmpty else { return .disabled }
        if enabled.contains(where: { $0.fiberPhase == "failed" }) { return .failed }
        if enabled.allSatisfy({ $0.fiberPhase == "active" }) { return .active }
        if enabled.contains(where: { $0.fiberPhase == "active" }),
           enabled.allSatisfy({ $0.fiberPhase == "active" || $0.fiberPhase == "pending" }) {
            return .partial
        }
        return .pending
    }
}

enum PluginVersions {
    static func valid(_ value: String) -> Bool {
        value.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\\+[0-9A-Za-z.-]+)?$", options: .regularExpression) != nil
    }

    static func isNewer(_ target: String, than installed: String) -> Bool {
        guard valid(target), valid(installed) else { return false }
        func parts(_ value: String) -> ([Int], [String]) {
            let version = value.split(separator: "+", maxSplits: 1)[0]
            let pieces = version.split(separator: "-", maxSplits: 1)
            return (pieces[0].split(separator: ".").compactMap { Int($0) },
                    pieces.count == 2 ? pieces[1].split(separator: ".").map(String.init) : [])
        }
        let (lhs, leftPre) = parts(target), (rhs, rightPre) = parts(installed)
        guard lhs.count == 3, rhs.count == 3 else { return false }
        if lhs != rhs { return rhs.lexicographicallyPrecedes(lhs) }
        if leftPre.isEmpty { return !rightPre.isEmpty }
        if rightPre.isEmpty { return false }
        for (left, right) in zip(leftPre, rightPre) where left != right {
            switch (Int(left), Int(right)) {
            case let (a?, b?): return a > b
            case (_?, nil): return false
            case (nil, _?): return true
            case (nil, nil): return left > right
            }
        }
        return leftPre.count > rightPre.count
    }
}

struct PluginOperationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Filesystem operations are separate from UI/service control so recovery can be
/// exercised against disposable profiles without touching the user's installation.
enum PluginFiles {
    static func validName(_ name: String) -> Bool {
        name.range(of: "^(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$", options: .regularExpression) != nil
    }

    static func load(profile: URL) throws -> [ManagedPlugin] {
        let manifest = profile.appendingPathComponent("package.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any] else {
            throw PluginOperationError(message: "插件配置 package.json 格式无效。")
        }
        guard let dependencies = root["dependencies"] as? [String: String] else {
            if root["dependencies"] == nil { return [] }
            throw PluginOperationError(message: "插件 dependencies 格式无效。")
        }
        let builtInBundles: Set<String> = ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app", "@deepseek-ai/dsh-headless"]
        return try dependencies.filter { !builtInBundles.contains($0.key) }.sorted(by: { $0.key < $1.key }).map { name, requirement in
            guard validName(name) else { throw PluginOperationError(message: "插件包名无效：\(name)") }
            let installed = profile.appendingPathComponent("node_modules/\(name)/package.json")
            let package = (try? Data(contentsOf: installed)).flatMap {
                (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
            }
            // Git, local paths, aliases and tarballs need their original source's
            // update policy; never silently substitute an npm package of the same name.
            let registry = requirement.range(of: "^[0-9v~^<>=*| .xX-][0-9A-Za-z~^<>=*| .+-]*$", options: .regularExpression) != nil
                || requirement.range(of: "^[a-zA-Z][a-zA-Z0-9._-]*$", options: .regularExpression) != nil
            return ManagedPlugin(name: name, requirement: requirement,
                                 installedVersion: package?["version"] as? String, registryManaged: registry)
        }
    }

    static func backups(root: URL, profile: URL) -> [PluginBackup] {
        let directories = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return directories.compactMap { directory in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("backup.json")),
                  let backup = try? JSONDecoder().decode(PluginBackup.self, from: data),
                  backup.id == directory.lastPathComponent,
                  backup.profilePath == profile.standardizedFileURL.path,
                  FileManager.default.fileExists(atPath: directory.appendingPathComponent("profile/package.json").path)
            else { return nil }
            return backup
        }.sorted { $0.createdAt > $1.createdAt }
    }

    static func backup(profile: URL, root: URL, reason: String, allowIncomplete: Bool = false) throws -> PluginBackup {
        let fm = FileManager.default
        guard fm.fileExists(atPath: profile.path),
              allowIncomplete || fm.fileExists(atPath: profile.appendingPathComponent("package.json").path) else {
            throw PluginOperationError(message: "找不到 Web 插件配置，无法创建备份。")
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let backup = PluginBackup(id: UUID().uuidString, createdAt: Date(), reason: reason,
                                  profilePath: profile.standardizedFileURL.path)
        let directory = root.appendingPathComponent(backup.id)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            // Include node_modules: rollback should also work offline after a
            // partially failed installation, without resolving newer dependencies.
            try fm.copyItem(at: profile, to: directory.appendingPathComponent("profile"))
            try JSONEncoder().encode(backup).write(to: directory.appendingPathComponent("backup.json"), options: .atomic)
            return backup
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }

    static func restore(_ backup: PluginBackup, profile: URL, root: URL) throws {
        guard backups(root: root, profile: profile).contains(where: { $0.id == backup.id }) else {
            throw PluginOperationError(message: "备份无效或属于其他 profile。")
        }
        let fm = FileManager.default
        let parent = profile.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(".plugin-restore-\(UUID().uuidString)")
        let displaced = parent.appendingPathComponent(".plugin-previous-\(UUID().uuidString)")
        try fm.copyItem(at: root.appendingPathComponent(backup.id + "/profile"), to: staged)
        defer { try? fm.removeItem(at: staged) }
        try fm.moveItem(at: profile, to: displaced)
        do {
            try fm.moveItem(at: staged, to: profile)
        } catch {
            do { try fm.moveItem(at: displaced, to: profile) }
            catch { throw PluginOperationError(message: "恢复中断，原 profile 保留在 \(displaced.path)，请从备份恢复。") }
            throw error
        }
        // A separate pre-restore backup is retained by the caller.
        try? fm.removeItem(at: displaced)
    }
}

/// Advisory lock shared across desktop app instances. The CLI itself does not
/// participate, so the UI also tells users not to run concurrent plugin commands.
final class PluginProfileLock {
    private let descriptor: Int32
    init(profile: URL) throws {
        descriptor = open(profile.deletingLastPathComponent().appendingPathComponent(".desktop-web-plugins.lock").path,
                          O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw PluginOperationError(message: "无法锁定插件目录。") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw PluginOperationError(message: "另一个客户端正在管理插件，请等待其完成。")
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}
