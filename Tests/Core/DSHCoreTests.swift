import Foundation
import Testing
@testable import DSHCore

struct DSHCoreTests {
    @Test
    func testArgumentsStayLiteralAndPreserveQuotedEmptyValues() {
        #expect(parseCommandArguments(#"--model "/a path/model" '' 'literal $(touch nope)'"#) == ["--model", "/a path/model", "", "literal $(touch nope)"])
        #expect(parseCommandArguments(#"hello\ world 'a\b'"#) == ["hello world", #"a\b"#])
        #expect(parseCommandArguments("'unfinished") == nil)
        #expect(parseCommandArguments("unfinished\\") == nil)
    }

    @Test
    func testMaintenancePermitCannotBeUsedByAnotherService() throws {
        let name = "dsh-core-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("/missing/test-dsh", forKey: "dshPath")
        let first = DSHService(defaults: defaults, monitor: false)
        let second = DSHService(defaults: defaults, monitor: false)
        let permit = try #require(first.beginMaintenance())
        #expect(first.beginMaintenance() == nil)
        first.start()
        #expect(first.state == .stopped, "ordinary startup must be held during maintenance")
        let otherPermit = try #require(second.beginMaintenance())
        first.endMaintenance(otherPermit)
        #expect(first.isMaintaining)
        first.endMaintenance(permit)
        #expect(!(first.isMaintaining))
        #expect(!(first.ownsProcess))
        second.endMaintenance(otherPermit)
    }

    @Test
    func testRuntimePersistenceDoesNotWriteFeaturePreferences() throws {
        let name = "dsh-persistence-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("/missing/test-dsh", forKey: "dshPath")
        let service = DSHService(defaults: defaults, monitor: false)
        defaults.set("independently changed", forKey: "localModelName")
        defaults.set(false, forKey: "captureModelRequests")
        defaults.set(false, forKey: "simplifyPluginInventory")
        service.port = 3099
        service.persist()
        #expect(defaults.integer(forKey: "port") == 3099)
        #expect(defaults.string(forKey: "localModelName") == "independently changed")
        #expect(!(defaults.bool(forKey: "captureModelRequests")))
        #expect(!(defaults.bool(forKey: "simplifyPluginInventory")))
    }
}
