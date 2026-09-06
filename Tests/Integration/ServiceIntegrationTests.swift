import Darwin
import Foundation
import Testing
import DSHCore
import LocalModelFeature

/// Exercise the real process and health-check code against disposable HTTP children.
/// No installed runtime, model weights, provider or user data is used.
@Suite(.serialized) @MainActor
struct ServiceIntegrationTests {
    @Test
    func runtimeStartMaintenanceRestartAndStop() async throws {
        let fixture = try HTTPFixture()
        defer { fixture.remove() }
        let log = ActivityLog()
        var preparations = 0
        var cleanups = 0
        let patch = fixture.root.appendingPathComponent("literal patch ' $.yml").path
        let runtime = DSHService(defaults: fixture.defaults, prepareLaunch: {
            preparations += 1
            return DSHLaunchPreparation(arguments: ["--patch", patch], messages: ["Prepared fixture"])
        }, cleanUpLaunch: { cleanups += 1 }, log: log.append, monitor: false)
        defer { runtime.terminateOnQuit() }

        runtime.start()
        try await waitFor("runtime HTTP readiness") { runtime.state.webReady && runtime.ownsProcess }
        let arguments = try JSONDecoder().decode([String].self, from: Data(contentsOf: fixture.argumentsFile))
        #expect(arguments == ["web", "--patch", patch, "--host", "127.0.0.1", "--port", String(fixture.port), "--no-open"])
        #expect(log.text.contains("Prepared fixture"))

        let first = try #require(runtimePID(runtime))
        let token = try #require(runtime.beginMaintenance())
        runtime.stop()
        runtime.restart()
        #expect(runtimePID(runtime) == first, "ordinary controls must not interrupt maintenance")
        runtime.stop(maintenance: token)
        try await waitFor("maintenance stop") { runtime.state == .stopped && !runtime.ownsProcess }
        #expect(cleanups == 1)
        runtime.start(maintenance: token)
        try await waitFor("maintenance startup") { runtime.state.webReady && runtime.ownsProcess }
        runtime.endMaintenance(token)
        let second = try #require(runtimePID(runtime))
        #expect(second != first)

        runtime.restart()
        try await waitFor("ordinary restart") {
            runtime.state.webReady && runtime.ownsProcess && runtimePID(runtime) != second
        }
        #expect(preparations == 3)
        #expect(cleanups == 2)
        runtime.stop()
        try await waitFor("final stop and port release") {
            runtime.state == .stopped && !runtime.ownsProcess && listeningPid(port: fixture.port) == nil
        }
        #expect(cleanups == 3)
    }

    @Test
    func localModelHealthFailureRecoveryAndStopStayIndependent() async throws {
        let fixture = try HTTPFixture()
        defer { fixture.remove() }
        let node = fixture.nodeExecutable
        fixture.defaults.set(node, forKey: "localModelStartExecutable")
        fixture.defaults.set("\"\(fixture.script.path)\" --port \(fixture.port)", forKey: "localModelStartArguments")
        fixture.defaults.set("http://127.0.0.1:\(fixture.port)/health", forKey: "localModelHealthURL")
        let model = LocalModelService(defaults: fixture.defaults, monitor: false)
        let runtime = DSHService(defaults: fixture.defaults, monitor: false)
        defer { model.terminateOnQuit() }
        model.startLocalModel()
        try await waitFor("model fixture listener") { listeningPid(port: fixture.port) != nil }
        model.refreshLocalModel()
        try await waitFor("model healthy") { model.localModelState == .ready }
        #expect(runtime.state == .stopped)
        #expect(!runtime.ownsProcess)

        model.localModelHealthURL = "http://127.0.0.1:\(fixture.port)/unhealthy"
        model.refreshLocalModel()
        try await waitFor("model HTTP failure") {
            if case .failed(let reason) = model.localModelState { return reason.contains("503") }
            return false
        }
        #expect(runtime.state == .stopped)
        model.localModelHealthURL = "http://127.0.0.1:\(fixture.port)/health"
        model.refreshLocalModel()
        try await waitFor("model recovery") { model.localModelState == .ready }
        model.stopLocalModel()
        try await waitFor("model stopped and port released") {
            model.localModelState == .stopped && listeningPid(port: fixture.port) == nil
        }
        #expect(runtime.state == .stopped)
    }

    @Test
    func externalRuntimeIsAdoptedWithoutBecomingOwned() async throws {
        let fixture = try HTTPFixture()
        defer { fixture.remove() }
        let node = fixture.nodeExecutable
        let child = Process()
        child.executableURL = URL(fileURLWithPath: node)
        child.arguments = [fixture.script.path, "web", "--port", String(fixture.port)]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        try await waitFor("external fixture listener") { listeningPid(port: fixture.port) == child.processIdentifier }
        let runtime = DSHService(defaults: fixture.defaults, monitor: false)
        runtime.startIfNeeded()
        try await waitFor("healthy external adoption") { runtime.state == .externalRunning(child.processIdentifier) }
        #expect(!runtime.ownsProcess)
        runtime.terminateOnQuit()
        #expect(child.isRunning, "quitting must leave an unowned external service running")
        child.terminate()
        try await waitFor("external service exit") { !child.isRunning }
        runtime.refreshExternal()
        try await waitFor("external state cleared") { runtime.state == .stopped }
    }

    private func runtimePID(_ runtime: DSHService) -> Int32? {
        if case .running(let pid) = runtime.state { return pid }
        return nil
    }

    private func waitFor(_ operation: String, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while !condition() {
            if Date() >= deadline { throw FixtureError("Timed out waiting for \(operation)") }
            pumpTimers()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // The command-line test host needs a run loop for the app's readiness timers.
    private func pumpTimers() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
}

private struct FixtureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private final class HTTPFixture {
    let root: URL
    let script: URL
    let argumentsFile: URL
    let defaults: UserDefaults
    let domain: String
    let port: Int
    let nodeExecutable: String

    init() throws {
        nodeExecutable = try #require(findNodeExecutable() ?? shellOut("/usr/bin/which", ["node"]))
        let name = "dsh-integration-\(UUID().uuidString)"
        root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        script = root.appendingPathComponent("dsh-fixture.js")
        argumentsFile = root.appendingPathComponent("arguments.json")
        domain = name
        defaults = try #require(UserDefaults(suiteName: name))
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw FixtureError("Cannot reserve a fixture port: \(errno)") }
        defer { close(socketFD) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw FixtureError("Cannot bind a fixture port: \(errno)") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &length) }
        }
        guard result == 0 else { throw FixtureError("Cannot read the fixture port: \(errno)") }
        port = Int(UInt16(bigEndian: address.sin_port))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(Self.server.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        defaults.set(script.path, forKey: "dshPath")
        defaults.set("127.0.0.1", forKey: "host")
        defaults.set(port, forKey: "port")
        defaults.set(false, forKey: "autoStart")
        defaults.set(false, forKey: "cleanupStaleOnStart")
    }

    func remove() {
        defaults.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: root)
    }

    private static let server = #"""
    #!/usr/bin/env node
    const http = require('node:http');
    const fs = require('node:fs');
    const path = require('node:path');
    const args = process.argv.slice(2);
    const port = Number(args[args.indexOf('--port') + 1]);
    const server = http.createServer((request, response) => {
      response.writeHead(request.url === '/unhealthy' ? 503 : 200, { 'Content-Type': 'text/plain' });
      response.end('Disposable DSH desktop integration fixture');
    });
    server.listen(port, '127.0.0.1', () => {
      fs.writeFileSync(path.join(__dirname, 'arguments.json'), JSON.stringify(args));
      console.log('Fixture ready');
    });
    process.on('SIGTERM', () => server.close(() => process.exit(0)));
    """#
}
