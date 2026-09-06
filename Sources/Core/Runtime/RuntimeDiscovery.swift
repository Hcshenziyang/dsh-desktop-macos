import Foundation

/// 常见 dsh 可执行文件候选位置（按优先级）
package func dshCandidates() -> [String] {
    var list: [String] = []
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    // 稳定安装位置（不受 npm/npx 缓存清理影响）
    let stable = home + "/.dsh/app/node_modules/.bin/dsh"
    if FileManager.default.isExecutableFile(atPath: stable) {
        list.append(stable)
    }
    let npxRoot = home + "/.npm/_npx"
    if let dirs = try? FileManager.default.contentsOfDirectory(atPath: npxRoot) {
        var bins: [(path: String, date: Date)] = []
        for d in dirs {
            let b = npxRoot + "/" + d + "/node_modules/.bin/dsh"
            guard FileManager.default.isExecutableFile(atPath: b) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: b)
            let date = (attrs?[.modificationDate] as? Date) ?? .distantPast
            bins.append((b, date))
        }
        list += bins.sorted { $0.date > $1.date }.map { $0.path }
    }
    list += [
        "/opt/homebrew/bin/dsh",
        "/usr/local/bin/dsh",
        home + "/.npm-global/bin/dsh",
        "/usr/bin/dsh",
        "/bin/dsh",
    ]
    return list
}

/// 解析 dsh 路径：优先用户保存的，其次自动探测
package func resolveDshPath(defaults: UserDefaults = .standard) -> String {
    if let stored = defaults.string(forKey: "dshPath"),
       FileManager.default.isExecutableFile(atPath: stored) {
        return stored
    }
    for c in dshCandidates() where FileManager.default.isExecutableFile(atPath: c) {
        defaults.set(c, forKey: "dshPath")
        return c
    }
    return ""
}

/// 解析 dsh 路径背后的真实脚本文件（跟随符号链接，支持相对链接）
package func resolvedScriptPath(_ path: String) -> String {
    var current = path
    for _ in 0..<8 { // 防循环链接
        guard let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: current) else {
            return current
        }
        if resolved.hasPrefix("/") {
            current = resolved
        } else {
            let dir = (current as NSString).deletingLastPathComponent
            current = dir + "/" + resolved
        }
    }
    return current
}

/// 查找 Node.js 可执行文件，用于直接解释 dsh 脚本（避免 GUI 应用环境 PATH 不完整导致 shebang 找不到 node）
package func findNodeExecutable() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let staticCandidates: [String] = [
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        home + "/.nvm/versions/node/default/bin/node",
    ]
    for c in staticCandidates where FileManager.default.isExecutableFile(atPath: c) {
        return c
    }
    // 动态扫描 nvm / workbuddy 等版本管理目录
    let versionRoots = [
        home + "/.nvm/versions/node",
        home + "/.workbuddy/binaries/node/versions",
    ]
    for root in versionRoots {
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
        var nodes: [(path: String, date: Date)] = []
        for v in versions {
            let nodePath = root + "/" + v + "/bin/node"
            guard FileManager.default.isExecutableFile(atPath: nodePath) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: nodePath)
            let date = (attrs?[.modificationDate] as? Date) ?? .distantPast
            nodes.append((nodePath, date))
        }
        if let latest = nodes.sorted(by: { $0.date > $1.date }).first {
            return latest.path
        }
    }
    return nil
}

/// 查找与 Node.js 配套的 npm，用于在用户确认后安装官方 DSH 运行时。
package func findNpmExecutable() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var candidates = [
        "/opt/homebrew/bin/npm",
        "/usr/local/bin/npm",
        home + "/.nvm/versions/node/default/bin/npm",
    ]
    if let node = findNodeExecutable() {
        candidates.insert((node as NSString).deletingLastPathComponent + "/npm", at: 0)
    }
    candidates += dynamicNodeBinDirs(home: home).map { $0 + "/npm" }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// 把常见 Node 安装目录加入 PATH，确保 dsh 的 shebang `#!/usr/bin/env node` 能找到解释器
package func enrichedEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let nodeDirs = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        home + "/.nvm/versions/node/default/bin",
        home + "/.workbuddy/binaries/node/versions/current/bin",
    ] + dynamicNodeBinDirs(home: home)
    let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
    let additions = nodeDirs.filter { FileManager.default.fileExists(atPath: $0) && !existing.contains($0) }
    if !additions.isEmpty {
        env["PATH"] = (additions + existing).joined(separator: ":")
    }
    return env
}

package func dynamicNodeBinDirs(home: String) -> [String] {
    var dirs: [String] = []
    for root in [home + "/.nvm/versions/node", home + "/.workbuddy/binaries/node/versions"] {
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
        for v in versions {
            let binDir = root + "/" + v + "/bin"
            if FileManager.default.fileExists(atPath: binDir + "/node") {
                dirs.append(binDir)
            }
        }
    }
    return dirs
}
