@testable import DatabaseCore
import Foundation
import Testing

struct TableTests {
    private func makeTempTable() throws -> (Table, String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
            .path
        let table = try Table(filename: path)
        return (table, path)
    }

    @Test func `insert and select one row`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let row = Row(id: 1, username: "foo", email: "foo@example.com")
        #expect(table.insert(row: row) == .success)
        #expect(table.select() == [row])
    }

    @Test func `insert beyond one leaf node capacity`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        for i: UInt32 in 1 ... 15 {
            let row = Row(id: i, username: "user\(i)", email: "user\(i)@example.com")
            #expect(table.insert(row: row) == .success)
        }
    }

    @Test func `insert and select two rows`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let row1 = Row(id: 1, username: "foo", email: "foo@example.com")
        let row2 = Row(id: 2, username: "bob", email: "bob@example.com")
        table.insert(row: row1)
        table.insert(row: row2)
        #expect(table.select() == [row1, row2])
    }
}
