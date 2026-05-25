import Foundation

struct Cursor: IteratorProtocol, Sequence {
    let btree: BTree
    var pageNum: UInt32
    var cellNum: UInt32
    var endOfTable: Bool

    mutating func next() -> Row? {
        guard !endOfTable else { return nil }
        let page = btree.pager.getPage(Int(pageNum))
        let offset = LeafNode.valueOffset(cellNum: Int(cellNum))
        let row = Row.deserialize(from: Data(page[offset ..< offset + Row.size]))
        advance()
        return row
    }

    mutating func advance() {
        let node = LeafNode(btree.pager.getPage(Int(pageNum)))
        cellNum += 1
        if cellNum >= UInt32(node.cells.count) {
            let nextPageNum = node.nextLeaf
            if nextPageNum == 0 {
                endOfTable = true
            } else {
                pageNum = nextPageNum
                cellNum = 0
            }
        }
    }
}
