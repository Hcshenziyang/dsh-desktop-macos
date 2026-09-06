import Foundation
import Darwin

package struct ProcessCommandError: LocalizedError {
    package let message: String
    package var errorDescription: String? { message }
}

package struct ProcessCommandResult {
    package let status: Int32
    package let output: String
}

package enum ProcessCommand {
    /// Spawn into a dedicated process group so timeout stops pnpm and lifecycle
    /// scripts together. Explicit argv/env and cwd never pass through a shell.
    package static func run(executable: String, arguments: [String], directory: URL,
                    environment: [String: String], timeout: TimeInterval = 300) async throws -> ProcessCommandResult {
        try await Task.detached(priority: .userInitiated) {
            let pipe = Pipe()
            let readFD = pipe.fileHandleForReading.fileDescriptor
            let writeFD = pipe.fileHandleForWriting.fileDescriptor
            var actions: posix_spawn_file_actions_t?
            var attributes: posix_spawnattr_t?
            posix_spawn_file_actions_init(&actions)
            posix_spawnattr_init(&attributes)
            defer {
                posix_spawn_file_actions_destroy(&actions)
                posix_spawnattr_destroy(&attributes)
                try? pipe.fileHandleForReading.close()
            }
            posix_spawn_file_actions_addchdir_np(&actions, directory.path)
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
            posix_spawn_file_actions_adddup2(&actions, writeFD, STDOUT_FILENO)
            posix_spawn_file_actions_adddup2(&actions, writeFD, STDERR_FILENO)
            posix_spawn_file_actions_addclose(&actions, readFD)
            posix_spawn_file_actions_addclose(&actions, writeFD)
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
            posix_spawnattr_setpgroup(&attributes, 0)
            var argv = ([executable] + arguments).map { strdup($0) } + [nil]
            var envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer {
                argv.forEach { free($0) }
                envp.forEach { free($0) }
            }
            var pid: pid_t = 0
            let launchError = posix_spawn(&pid, executable, &actions, &attributes, &argv, &envp)
            try? pipe.fileHandleForWriting.close()
            guard launchError == 0 else {
                throw ProcessCommandError(message: "无法执行插件命令：\(String(cString: strerror(launchError)))")
            }
            _ = fcntl(readFD, F_SETFL, O_NONBLOCK)
            let deadline = ProcessInfo.processInfo.systemUptime + timeout
            var output = Data()
            var buffer = [UInt8](repeating: 0, count: 16_384)
            var status: Int32 = 0
            var exited = false
            var timedOut = false
            while true {
                let count = read(readFD, &buffer, buffer.count)
                if count > 0 {
                    output.append(contentsOf: buffer.prefix(count))
                    if output.count > 262_144 { output = Data(output.suffix(262_144)) }
                }
                if !exited { exited = waitpid(pid, &status, WNOHANG) == pid }
                if exited && count <= 0 { break }
                if !exited && !timedOut && ProcessInfo.processInfo.systemUptime >= deadline {
                    timedOut = true
                    kill(-pid, SIGKILL)
                }
                if count <= 0 { usleep(20_000) }
            }
            let text = String(decoding: output, as: UTF8.self)
            if timedOut {
                throw ProcessCommandError(message: "插件命令超时，已停止安装进程。\n\(text.suffix(1500))")
            }
            let exitCode = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            return ProcessCommandResult(status: exitCode, output: text)
        }.value
    }
}
