import Foundation

public enum ExecuteError: Error {
    case duplicateKey
    case tableFull
}

public class Table {
    let btree: BTree

    public init(filename: String) throws {
        let pager = try Pager(filename: filename)
        btree = try BTree(pager: pager)
    }

    public func close() {
        btree.close()
    }

    public func insert(row: Row) throws(ExecuteError) {
        try btree.insert(row: row)
    }

    public func select() -> [Row] {
        Array(btree.rows)
    }
}
