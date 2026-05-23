@testable import DatabaseCore
import Foundation
import Testing

struct CursorTests {
    private func makeTempTable() throws -> (Table, String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
            .path
        let table = try Table(filename: path)
        return (table, path)
    }

    @Test func `tableStart on empty table has endOfTable true`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let cursor = table.tableStart()
        #expect(cursor.endOfTable == true)
        #expect(cursor.rowNum == 0)
    }

    @Test func `tableStart on non-empty table positions at row 0`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        table.insert(row: Row(id: 1, username: "a", email: "a@example.com"))
        let cursor = table.tableStart()
        #expect(cursor.rowNum == 0)
        #expect(cursor.endOfTable == false)
    }

    @Test func `tableEnd positions past last row`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        table.insert(row: Row(id: 1, username: "a", email: "a@example.com"))
        table.insert(row: Row(id: 2, username: "b", email: "b@example.com"))
        let cursor = table.tableEnd()
        #expect(cursor.rowNum == 2)
        #expect(cursor.endOfTable == true)
    }

    @Test func `value returns correct pageIndex and byteOffset`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        // Row 0: page 0, offset 0
        let c0 = Cursor(table: table, rowNum: 0, endOfTable: false)
        #expect(c0.value() == (pageIndex: 0, byteOffset: 0))

        // Row 1: page 0, offset Row.size
        let c1 = Cursor(table: table, rowNum: 1, endOfTable: false)
        #expect(c1.value() == (pageIndex: 0, byteOffset: Row.size))

        // Row at start of page 1: rowsPerPage rows in
        let c2 = Cursor(table: table, rowNum: UInt32(Table.rowsPerPage), endOfTable: false)
        #expect(c2.value() == (pageIndex: 1, byteOffset: 0))
    }

    @Test func `advance progresses to next row`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        table.insert(row: Row(id: 1, username: "a", email: "a@example.com"))
        table.insert(row: Row(id: 2, username: "b", email: "b@example.com"))
        let cursor = table.tableStart()
        #expect(cursor.rowNum == 0)
        cursor.advance()
        #expect(cursor.rowNum == 1)
        #expect(cursor.endOfTable == false)
    }

    @Test func `advance sets endOfTable after last row`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        table.insert(row: Row(id: 1, username: "a", email: "a@example.com"))
        let cursor = table.tableStart()
        cursor.advance()
        #expect(cursor.endOfTable == true)
    }
}
