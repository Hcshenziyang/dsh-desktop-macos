import Foundation
import Testing
@testable import ProjectViewsFeature

struct ProjectFilesTests {
    func fixture() throws -> (URL, URL, ProjectFiles) {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-project-files-\(UUID().uuidString)")
        let project = temporary.appendingPathComponent("project")
        let storage = temporary.appendingPathComponent("storages")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let json: [String: Any] = ["tables": ["workspaces": ["first": ["path": project.path, "sessionIds": ["session"]]]]]
        try JSONSerialization.data(withJSONObject: json).write(to: storage.appendingPathComponent("workspace.json"))
        return (temporary, project, ProjectFiles(dataRoot: temporary))
    }

    @Test func navigationStaysInsideRegisteredProject() throws {
        let (temporary, project, files) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let outside = temporary.appendingPathComponent("private.txt")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("outside"), withDestinationURL: outside)
        #expect(throws: (any Error).self) { try files.preview(workspaceID: "first", path: "../private.txt") }
        #expect(throws: (any Error).self) { try files.preview(workspaceID: "first", path: "outside") }
        #expect(throws: (any Error).self) { try files.resolve(workspaceID: "first", relativePath: outside.path) }
        #expect(throws: (any Error).self) { try files.root(workspaceID: "missing") }
        let listing = try files.list(workspaceID: "first", path: "", showHidden: false)
        let entry = try #require((listing["entries"] as? [[String: Any]])?.first)
        #expect(entry["accessible"] as? Bool == false)
    }

    @Test func listsOneLevelAndIncludesHiddenFilesOnlyOnRequest() throws {
        let (temporary, project, files) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: project.appendingPathComponent("notes"), withIntermediateDirectories: false)
        try Data().write(to: project.appendingPathComponent("notes/inside.txt"))
        try Data().write(to: project.appendingPathComponent(".hidden"))
        try Data().write(to: project.appendingPathComponent("article.txt"))
        let normal = try files.list(workspaceID: "first", path: "", showHidden: false)["entries"] as? [[String: Any]]
        #expect(normal?.compactMap { $0["name"] as? String } == ["notes", "article.txt"])
        let all = try files.list(workspaceID: "first", path: "", showHidden: true)["entries"] as? [[String: Any]]
        #expect(all?.count == 3)
        let nested = try files.list(workspaceID: "first", path: "notes", showHidden: false)["entries"] as? [[String: Any]]
        #expect(nested?.first?["path"] as? String == "notes/inside.txt")
    }

    @Test func previewsAreBoundedTextWithoutRenderingActiveContent() throws {
        let (temporary, project, files) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let html = "<script>alert('never execute')</script>中文"
        try Data(html.utf8).write(to: project.appendingPathComponent("page.html"))
        try Data([0, 1, 2]).write(to: project.appendingPathComponent("binary.dat"))
        try Data(repeating: 65, count: ProjectFiles.previewLimit + 1).write(to: project.appendingPathComponent("large.txt"))
        let result = try files.preview(workspaceID: "first", path: "page.html")
        #expect(result["kind"] as? String == "text")
        #expect(result["text"] as? String == html)
        #expect(try files.preview(workspaceID: "first", path: "binary.dat")["kind"] as? String == "unsupported")
        #expect(try files.preview(workspaceID: "first", path: "large.txt")["kind"] as? String == "unsupported")
    }

    @Test func removedAndMovedProjectsDoNotUseStaleRoots() throws {
        let (temporary, project, files) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        #expect(try files.root(workspaceID: "first") == project.resolvingSymlinksInPath())
        try FileManager.default.removeItem(at: project)
        #expect(throws: (any Error).self) { try files.list(workspaceID: "first", path: "", showHidden: false) }
    }

    @Test func markdownRoundTripPreservesEncodingAndFilePermissions() throws {
        let (temporary, project, files) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let url = project.appendingPathComponent("文章.md")
        var original = Data([0xEF, 0xBB, 0xBF]); original.append(Data("# 标题\r\n\r\n正文\r\n".utf8))
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let markdown = MarkdownFile(files: files), document = try markdown.read(workspaceID: "first", path: "文章.md")
        #expect(document["text"] as? String == "# 标题\n\n正文\n")
        let version = try #require(document["version"] as? String)
        let saved = try markdown.save(workspaceID: "first", path: "文章.md", text: "# 新标题\n\n新的内容\n", expectedVersion: version)
        let actual = try Data(contentsOf: url)
        #expect(actual.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(String(decoding: actual, as: UTF8.self).contains("\r\n"))
        #expect(saved["text"] as? String == "# 新标题\n\n新的内容\n")
        #expect(saved["version"] as? String != version)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
    }

    @Test func markdownConflictNeverOverwritesAnExternalEdit() throws {
        let (temporary, project, files) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let url = project.appendingPathComponent("article.md")
        try Data("original".utf8).write(to: url)
        let markdown = MarkdownFile(files: files)
        let version = try #require(markdown.read(workspaceID: "first", path: "article.md")["version"] as? String)
        try Data("Agent updated this".utf8).write(to: url, options: .atomic)
        #expect(throws: (any Error).self) { try markdown.save(workspaceID: "first", path: "article.md", text: "stale editor", expectedVersion: version) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "Agent updated this")
        try FileManager.default.removeItem(at: url)
        #expect(throws: (any Error).self) { try markdown.save(workspaceID: "first", path: "article.md", text: "do not recreate", expectedVersion: version) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func markdownWritesRejectOtherFileTypesAndEscapingLinks() throws {
        let (temporary, project, files) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let outside = temporary.appendingPathComponent("outside.md"), plain = project.appendingPathComponent("plain.txt")
        try Data("outside".utf8).write(to: outside); try Data("plain".utf8).write(to: plain)
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("escape.md"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("disguised.md"), withDestinationURL: plain)
        let markdown = MarkdownFile(files: files), version = String(repeating: "a", count: 64)
        for path in ["plain.txt", "escape.md", "disguised.md", "../outside.md"] {
            #expect(throws: (any Error).self) { try markdown.save(workspaceID: "first", path: path, text: "not allowed", expectedVersion: version) }
        }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "outside")
        #expect(try String(contentsOf: plain, encoding: .utf8) == "plain")
        try Data(repeating: 65, count: MarkdownFile.limit + 1).write(to: project.appendingPathComponent("large.md"))
        #expect(throws: (any Error).self) { try markdown.read(workspaceID: "first", path: "large.md") }
    }

    @Test @MainActor func viewPreferencesAreIndependentAndPersistAcrossBridgeInstances() async throws {
        let (temporary, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let name = "dsh-project-views-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let bridge = ProjectViewsBridge(dataRoot: temporary, defaults: defaults)
        func call(_ bridge: ProjectViewsBridge, _ request: [String: Any]) async throws -> [String: Any] {
            try await withCheckedThrowingContinuation { continuation in
                bridge.handle(request) { result, error in
                    if let error { continuation.resume(throwing: ProjectFileError.message(error)) }
                    else { continuation.resume(returning: result as? [String: Any] ?? [:]) }
                }
            }
        }
        let initial = try await call(bridge, ["action": "scope", "workspaceID": "first"])
        #expect(initial["mode"] as? String == "traditional")
        _ = try await call(bridge, ["action": "mode", "workspaceID": "first", "mode": "folder"])
        let reopened = ProjectViewsBridge(dataRoot: temporary, defaults: defaults)
        #expect(try await call(reopened, ["action": "scope", "workspaceID": "first"])["mode"] as? String == "folder")
        #expect(defaults.object(forKey: "project-view.second") == nil)
        #expect(defaults.object(forKey: "port") == nil)
    }
}
