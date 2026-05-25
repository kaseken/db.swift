import Foundation

public enum ExecuteResult {
    case success
    case duplicateKey
}

public class Table {
    let btree: BTree
    public init(filename: String, internalNodeMaxCells: Int? = nil) throws {
        let pager = try Pager(filename: filename)
        let maxCells = internalNodeMaxCells
            ?? (Pager.pageSize - InternalNode.headerSize) / InternalNode.cellSize
        btree = BTree(pager: pager, internalNodeMaxCells: maxCells)
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
