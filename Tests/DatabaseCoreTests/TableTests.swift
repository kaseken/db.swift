@testable import DatabaseCore
import Foundation
import Testing

struct TableTests {
    private func makeTempTable() throws -> (Table, String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
            .path
        return try (Table(filename: path), path)
    }

    @Test func `insert and select one row`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let row = Row(id: 1, username: "foo", email: "foo@example.com")
        try table.execute(.insert(row))
        #expect(Array(table.btree.rows) == [row])
    }

    @Test func `insert and select two rows`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let row1 = Row(id: 1, username: "foo", email: "foo@example.com")
        let row2 = Row(id: 2, username: "bob", email: "bob@example.com")
        try table.execute(.insert(row1))
        try table.execute(.insert(row2))
        #expect(Array(table.btree.rows) == [row1, row2])
    }

    @Test func `insert beyond one leaf node capacity`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        for i: UInt32 in 1 ... 15 {
            let row = Row(id: i, username: "user\(i)", email: "user\(i)@example.com")
            try table.execute(.insert(row))
        }
    }
}
