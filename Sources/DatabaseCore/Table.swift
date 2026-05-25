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
        for i in 0 ..< btree.pager.numPages {
            btree.pager.flush(pageNum: i, numBytes: Pager.pageSize)
        }
        btree.pager.close()
    }

    @discardableResult
    public func insert(row: Row) -> ExecuteResult {
        let cursor = btree.find(key: row.id)
        let node = LeafNode(btree.pager.getPage(Int(cursor.pageNum)))
        if cursor.cellNum < node.numCells {
            if node.key(cellNum: Int(cursor.cellNum)) == row.id {
                return .duplicateKey
            }
        }
        btree.leafNodeInsert(cursor: cursor, key: row.id, row: row)
        return .success
    }

    public func select() -> [Row] {
        let cursor = btree.start()
        var rows: [Row] = []
        while !cursor.endOfTable {
            let (pageIndex, byteOffset) = cursor.value()
            let page = btree.pager.getPage(pageIndex)
            let slice = Data(page[byteOffset ..< byteOffset + Row.size])
            rows.append(Row.deserialize(from: slice))
            cursor.advance()
        }
        return rows
    }

    // MARK: - Forwarding shims (used by tests)

    var pager: Pager {
        btree.pager
    }

    func tableStart() -> Cursor {
        btree.start()
    }

    func tableFind(key: UInt32) -> Cursor {
        btree.find(key: key)
    }

    func printTree(pageNum: UInt32 = 0, indentation: Int = 0) {
        btree.printTree(pageNum: pageNum, indentation: indentation)
    }
}
