@testable import DatabaseCore
import Testing

struct MetaCommandTests {
    @Test func `exit command`() {
        guard case .exit = MetaCommand(".exit") else {
            Issue.record("Expected .exit")
            return
        }
    }

    @Test func `unrecognized command`() {
        guard case let .unrecognized(cmd) = MetaCommand(".unknown") else {
            Issue.record("Expected .unrecognized")
            return
        }
        #expect(cmd == ".unknown")
    }

    @Test func `non meta command returns nil`() {
        #expect(MetaCommand("select") == nil)
    }
}
