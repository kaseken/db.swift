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

    @Test func `tableFind locates existing key in right leaf after split`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        // Insert 14 rows to trigger a leaf split; root becomes an internal node.
        // Left leaf: keys 1-7, right leaf: keys 8-14.
        for i: UInt32 in 1 ... 14 {
            table.insert(row: Row(id: i, username: "u\(i)", email: "u\(i)@example.com"))
        }
        // Key 10 lives in the right leaf (page 1, cell 2).
        let cursor = table.tableFind(key: 10)
        let page = table.pager.getPage(Int(cursor.pageNum))
        #expect(nodeType(page) == .leaf)
        #expect(LeafNode(page).key(cellNum: Int(cursor.cellNum)) == 10)
    }

    @Test func `tableFind locates existing key in left leaf after split`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        for i: UInt32 in 1 ... 14 {
            table.insert(row: Row(id: i, username: "u\(i)", email: "u\(i)@example.com"))
        }
        // Key 3 lives in the left leaf.
        let cursor = table.tableFind(key: 3)
        let page = table.pager.getPage(Int(cursor.pageNum))
        #expect(nodeType(page) == .leaf)
        #expect(LeafNode(page).key(cellNum: Int(cursor.cellNum)) == 3)
    }

    @Test func `tableFind returns insertion point for non-existing key in multi-level tree`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        for i: UInt32 in 1 ... 14 {
            table.insert(row: Row(id: i, username: "u\(i)", email: "u\(i)@example.com"))
        }
        // Key 15 does not exist; cursor should point to the insertion position at end of right leaf.
        let cursor = table.tableFind(key: 15)
        let page = table.pager.getPage(Int(cursor.pageNum))
        #expect(nodeType(page) == .leaf)
        #expect(cursor.endOfTable == true)
    }

    @Test func `tableFind traverses multiple internal node levels`() throws {
        // Manually build a 3-level tree to exercise the recursive internalNodeFind branch
        // (child is itself an internal node):
        //
        //   page 0 (root, internal): key=7 | left=page1, right=page2
        //   page 1 (internal):       key=3 | left=page3, right=page4
        //   page 2 (internal):       key=10| left=page5, right=page6
        //   page 3 (leaf): keys 1, 2, 3
        //   page 4 (leaf): keys 4, 5, 6, 7
        //   page 5 (leaf): keys 8, 9, 10
        //   page 6 (leaf): keys 11, 12
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }

        var root = InternalNode.makeNew()
        root.isRoot = true
        root.cells = [(child: 1, key: 7)]
        root.rightChild = 2
        table.pager.setPage(0, data: root.data)

        var leftInternal = InternalNode.makeNew()
        leftInternal.cells = [(child: 3, key: 3)]
        leftInternal.rightChild = 4
        table.pager.setPage(1, data: leftInternal.data)

        var rightInternal = InternalNode.makeNew()
        rightInternal.cells = [(child: 5, key: 10)]
        rightInternal.rightChild = 6
        table.pager.setPage(2, data: rightInternal.data)

        var leaf3 = LeafNode.makeNew()
        leaf3.cells = [1, 2, 3].map { k in (key: UInt32(k), value: Data(count: Row.size)) }
        table.pager.setPage(3, data: leaf3.data)

        var leaf4 = LeafNode.makeNew()
        leaf4.cells = [4, 5, 6, 7].map { k in (key: UInt32(k), value: Data(count: Row.size)) }
        table.pager.setPage(4, data: leaf4.data)

        var leaf5 = LeafNode.makeNew()
        leaf5.cells = [8, 9, 10].map { k in (key: UInt32(k), value: Data(count: Row.size)) }
        table.pager.setPage(5, data: leaf5.data)

        var leaf6 = LeafNode.makeNew()
        leaf6.cells = [11, 12].map { k in (key: UInt32(k), value: Data(count: Row.size)) }
        table.pager.setPage(6, data: leaf6.data)

        // key 2: root → leftInternal → leaf3 (cell 1)
        let c2 = table.tableFind(key: 2)
        #expect(c2.pageNum == 3 && c2.cellNum == 1)

        // key 9: root → rightInternal → leaf5 (cell 1)
        let c9 = table.tableFind(key: 9)
        #expect(c9.pageNum == 5 && c9.cellNum == 1)
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
