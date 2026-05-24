@testable import DatabaseCore
import Foundation
import Testing

struct MetaCommandTests {
    private func makeTempTable() throws -> (Table, String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
            .path
        let table = try Table(filename: path)
        return (table, path)
    }

    @Test func `exit command`() {
        guard case .exit = MetaCommand(".exit") else {
            Issue.record("Expected .exit")
            return
        }
    }

    @Test func `constants command`() {
        guard case .constants = MetaCommand(".constants") else {
            Issue.record("Expected .constants")
            return
        }
    }

    @Test func `btree command`() {
        guard case .btree = MetaCommand(".btree") else {
            Issue.record("Expected .btree")
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

    @Test func `exit command returns true from execute`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        #expect(MetaCommand.exit.execute(table: table) == true)
    }

    @Test func `unrecognized command returns false from execute`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        #expect(MetaCommand.unrecognized(".unknown").execute(table: table) == false)
    }
}
