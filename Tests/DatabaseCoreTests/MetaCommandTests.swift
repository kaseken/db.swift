@testable import DatabaseCore
import Testing

struct MetaCommandTests {
    @Test func exitCommand() {
        guard case .exit = MetaCommand(".exit") else {
            Issue.record("Expected .exit")
            return
        }
    }

    @Test func unrecognizedCommand() {
        guard case let .unrecognized(cmd) = MetaCommand(".unknown") else {
            Issue.record("Expected .unrecognized")
            return
        }
        #expect(cmd == ".unknown")
    }

    @Test func nonMetaCommandReturnsNil() {
        #expect(MetaCommand("select") == nil)
    }
}
