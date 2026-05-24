import Foundation

public enum ExecuteResult {
    case success
}

public class Table {
    // TODO: Will become var when root splits are implemented.
    let rootPageNum: UInt32 = 0
    let pager: Pager

    public init(filename: String) throws {
        let pager = try Pager(filename: filename)
        self.pager = pager
        if pager.numPages == 0 {
            var rootPage = pager.getPage(0)
            rootPage = LeafNode.initialize()
            pager.setPage(0, data: rootPage)
        }
    }

    public func close() {
        for i in 0 ..< pager.numPages {
            pager.flush(pageNum: i, numBytes: Pager.pageSize)
        }
        pager.close()
    }

    func tableStart() -> Cursor {
        let rootNode = pager.getPage(Int(rootPageNum))
        let numCells = LeafNode.numCells(rootNode)
        return Cursor(table: self, pageNum: rootPageNum, cellNum: 0, endOfTable: numCells == 0)
    }

    func tableEnd() -> Cursor {
        let rootNode = pager.getPage(Int(rootPageNum))
        let numCells = LeafNode.numCells(rootNode)
        return Cursor(table: self, pageNum: rootPageNum, cellNum: numCells, endOfTable: true)
    }

    @discardableResult
    public func insert(row: Row) -> ExecuteResult {
        let cursor = tableEnd()
        leafNodeInsert(cursor: cursor, key: row.id, row: row)
        return .success
    }

    private func leafNodeInsert(cursor: Cursor, key: UInt32, row: Row) {
        var node = pager.getPage(Int(cursor.pageNum))
        let numCells = LeafNode.numCells(node)
        if numCells >= UInt32(LeafNode.maxCells) {
            print("Need to implement splitting a leaf node.")
            Foundation.exit(1)
        }
        // TODO: Implement cell shifting in Part 9+ when binary search determines the insert position.
        // insert() currently always calls tableEnd(), so cursor.cellNum == numCells is guaranteed.
        assert(cursor.cellNum == numCells, "Mid-node insertion not yet implemented")
//        if cursor.cellNum < numCells {
//            var i = numCells
//            while i > cursor.cellNum {
//                let src = LeafNode.cellOffset(cellNum: Int(i) - 1)
//                let dst = LeafNode.cellOffset(cellNum: Int(i))
//                node.replaceSubrange(dst ..< dst + LeafNode.cellSize, with: node[src ..< src + LeafNode.cellSize])
//                i -= 1
//            }
//        }
        LeafNode.setNumCells(&node, numCells + 1)
        LeafNode.setKey(&node, cellNum: Int(cursor.cellNum), key: key)
        let serialized = row.serialize()
        let valueOff = LeafNode.valueOffset(cellNum: Int(cursor.cellNum))
        node.replaceSubrange(valueOff ..< valueOff + Row.size, with: serialized)
        pager.setPage(Int(cursor.pageNum), data: node)
    }

    public func select() -> [Row] {
        let cursor = tableStart()
        var rows: [Row] = []
        while !cursor.endOfTable {
            let (pageIndex, byteOffset) = cursor.value()
            let page = pager.getPage(pageIndex)
            let slice = Data(page[byteOffset ..< byteOffset + Row.size])
            rows.append(Row.deserialize(from: slice))
            cursor.advance()
        }
        return rows
    }

    func printTree() {
        let rootNode = pager.getPage(Int(rootPageNum))
        let numCells = LeafNode.numCells(rootNode)
        print("leaf (size \(numCells))")
        for i in 0 ..< numCells {
            let key = LeafNode.key(rootNode, cellNum: Int(i))
            print("  - \(i) : \(key)")
        }
    }
}
