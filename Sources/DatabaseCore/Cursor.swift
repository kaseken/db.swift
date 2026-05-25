import Foundation

struct Cursor: IteratorProtocol, Sequence {
    private let btree: BTree
    private(set) var pageNum: UInt32
    private(set) var cellNum: UInt32
    private(set) var endOfTable: Bool

    init(btree: BTree, pageNum: UInt32, cellNum: UInt32, endOfTable: Bool) {
        self.btree = btree
        self.pageNum = pageNum
        self.cellNum = cellNum
        self.endOfTable = endOfTable
    }

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
