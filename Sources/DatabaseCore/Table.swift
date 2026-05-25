import Foundation

public enum ExecuteResult {
    case success
    case duplicateKey
}

public class Table {
    let btree: BTree

    public init(filename: String) throws {
        let pager = try Pager(filename: filename)
        btree = BTree(pager: pager)
    }

    public func close() {
        btree.close()
    }

    @discardableResult
    public func insert(row: Row) -> ExecuteResult {
        btree.insert(row: row)
    }

    public func select() -> [Row] {
        Array(btree.rows)
    }
}
