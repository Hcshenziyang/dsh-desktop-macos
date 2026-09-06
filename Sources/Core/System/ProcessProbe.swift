import Foundation


/// 执行一条外部命令并返回合并后的 stdout/stderr
package func shellOut(_ path: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 查询监听某个 TCP 端口的进程 PID
package func listeningPid(port: Int) -> Int32? {
    guard let out = shellOut("/usr/sbin/lsof", ["-tiTCP:\(port)", "-sTCP:LISTEN"]) else { return nil }
    guard let first = out.split(separator: "\n").first, let pid = Int32(first) else { return nil }
    return pid
}

/// 查询进程的命令行
package func commandOf(pid: Int32) -> String {
    shellOut("/bin/ps", ["-p", "\(pid)", "-o", "command="]) ?? ""
}
