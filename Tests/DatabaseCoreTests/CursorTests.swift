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
        #expect(cursor.cellNum == 0)
    }

    @Test func `tableStart on non-empty table positions at cell 0`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        table.insert(row: Row(id: 1, username: "a", email: "a@example.com"))
        let cursor = table.tableStart()
        #expect(cursor.cellNum == 0)
        #expect(cursor.endOfTable == false)
    }

    @Test func `tableFind returns correct position for existing key`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        table.insert(row: Row(id: 1, username: "a", email: "a@example.com"))
        table.insert(row: Row(id: 2, username: "b", email: "b@example.com"))
        let cursor = table.tableFind(key: 1)
        #expect(cursor.cellNum == 0)
        #expect(cursor.endOfTable == false)
    }

    @Test func `tableFind returns insertion point for non-existing key`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        table.insert(row: Row(id: 1, username: "a", email: "a@example.com"))
        table.insert(row: Row(id: 2, username: "b", email: "b@example.com"))
        let cursor = table.tableFind(key: 3)
        #expect(cursor.cellNum == 2)
        #expect(cursor.endOfTable == true)
    }

    @Test func `value returns correct pageIndex and byteOffset`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let c0 = Cursor(table: table, pageNum: 0, cellNum: 0, endOfTable: false)
        #expect(c0.value() == (pageIndex: 0, byteOffset: LeafNode.valueOffset(cellNum: 0)))

        let c1 = Cursor(table: table, pageNum: 0, cellNum: 1, endOfTable: false)
        #expect(c1.value() == (pageIndex: 0, byteOffset: LeafNode.valueOffset(cellNum: 1)))

        let c12 = Cursor(table: table, pageNum: 0, cellNum: 12, endOfTable: false)
        #expect(c12.value() == (pageIndex: 0, byteOffset: LeafNode.valueOffset(cellNum: 12)))
    }

    @Test func `advance progresses to next cell`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        table.insert(row: Row(id: 1, username: "a", email: "a@example.com"))
        table.insert(row: Row(id: 2, username: "b", email: "b@example.com"))
        let cursor = table.tableStart()
        #expect(cursor.cellNum == 0)
        cursor.advance()
        #expect(cursor.cellNum == 1)
        #expect(cursor.endOfTable == false)
    }

    @Test func `advance sets endOfTable after last cell`() throws {
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
