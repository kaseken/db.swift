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

    @Test func `select all rows after leaf node split`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let rows: [Row] = (1 ... 15).map { i in
            Row(id: UInt32(i), username: "user\(i)", email: "user\(i)@example.com")
        }
        for row in rows {
            table.insert(row: row)
        }
        #expect(table.select() == rows)
    }

    @Test func `select all rows after two leaf splits`() throws {
        // Rows 1-13 fill the root leaf; row 14 triggers a root split (2 leaves).
        // Rows 15-20 fill the right leaf; row 21 triggers a non-root split (3 leaves).
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let rows: [Row] = (1 ... 21).map { i in
            Row(id: UInt32(i), username: "user\(i)", email: "user\(i)@example.com")
        }
        for row in rows {
            table.insert(row: row)
        }
        #expect(table.select() == rows)
    }

    @Test func `non-root split inserts new child into interior of internal node`() throws {
        // Inserts keys 15-28 first so rows 15-21 become the left child and 22-28 the right
        // child after the root split. Then inserting keys 1-7 fills and splits the left child,
        // producing a new sibling whose max key (21) is less than the right child's max key (28),
        // exercising the cell-shift branch in internalNodeInsert.
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let keys: [UInt32] = Array(15 ... 28) + Array(1 ... 7)
        for key in keys {
            table.insert(row: Row(id: key, username: "user\(key)", email: "user\(key)@example.com"))
        }
        let expected = (Array(1 ... 7) + Array(15 ... 28)).map { i in
            Row(id: UInt32(i), username: "user\(i)", email: "user\(i)@example.com")
        }
        #expect(table.select() == expected)
    }
}
