@testable import DatabaseCore
import Foundation
import Testing

struct TableTests {
    private func makeTempTable(internalNodeMaxCells: Int? = nil) throws -> (Table, String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
            .path
        let table = try Table(filename: path, internalNodeMaxCells: internalNodeMaxCells)
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

    @Test func `select all rows after internal node split`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let rows: [Row] = (1 ... 65).map { i in
            Row(id: UInt32(i), username: "user\(i)", email: "user\(i)@example.com")
        }
        for row in rows {
            table.insert(row: row)
        }
        #expect(table.select() == rows)
    }

    /// With internalNodeMaxCells=3, the root internal node fills after 4 leaf splits
    /// (rows 1-28), and row 35 triggers internalNodeSplitAndInsert with splittingRoot=true.
    @Test func `select all rows after root internal node split`() throws {
        let (table, path) = try makeTempTable(internalNodeMaxCells: 3)
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let rows: [Row] = (1 ... 35).map { i in
            Row(id: UInt32(i), username: "user\(i)", email: "user\(i)@example.com")
        }
        for row in rows {
            table.insert(row: row)
        }
        #expect(table.select() == rows)
    }

    /// Continuing from the 35-row root split, rows up to 51 fill a non-root
    /// internal node and trigger internalNodeSplitAndInsert with splittingRoot=false.
    @Test func `select all rows after non-root internal node split`() throws {
        let (table, path) = try makeTempTable(internalNodeMaxCells: 3)
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let rows: [Row] = (1 ... 51).map { i in
            Row(id: UInt32(i), username: "user\(i)", email: "user\(i)@example.com")
        }
        for row in rows {
            table.insert(row: row)
        }
        #expect(table.select() == rows)
    }

    // Exercises the cell-shift loop body in internalNodeInsert (the else branch where
    // childMaxKey < rightChild's max AND the new child goes before an existing cell).
    //
    // Construction:
    //   Phase 1: Fill root leaf with sparse keys [1,200,400,...,2400] then insert 2600 to
    //            split it → root internal: key[0]=1200, L1=[1,200,...,1200], L2=[1400,...,2600]
    //   Phase 2: Fill L2 with [1210..1260] then insert 1270 to split it →
    //            root: key[0]=1200, key[1]=1270, numKeys=2, L1, L2'=[1210-1270], L3=[1400-2600]
    //   Phase 3: Fill L1 (child[0]) with [2..7] then insert 8 to split it →
    //            updateInternalNodeKey changes key[0] from 1200 → 7;
    //            internalNodeInsert gets right sibling (max=1200) at index=1 < numKeys=2
    //            → stride(from:2, through:2) = [2] → cell-shift loop body executes.
    @Test func `cell-shift loop in internalNodeInsert fires when new sibling goes before existing cell`() throws {
        let (table, path) = try makeTempTable()
        defer {
            table.close()
            try? FileManager.default.removeItem(atPath: path)
        }
        let phase1: [UInt32] = [1, 200, 400, 600, 800, 1000, 1200, 1400, 1600, 1800, 2000, 2200, 2400, 2600]
        let phase2: [UInt32] = [1210, 1220, 1230, 1240, 1250, 1260, 1270]
        let phase3: [UInt32] = [2, 3, 4, 5, 6, 7, 8]
        for key in phase1 + phase2 + phase3 {
            table.insert(row: Row(id: key, username: "u\(key)", email: "\(key)@e.com"))
        }
        let allKeys = (phase1 + phase2 + phase3).sorted()
        let expected = allKeys.map { i in Row(id: i, username: "u\(i)", email: "\(i)@e.com") }
        #expect(table.select() == expected)
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
