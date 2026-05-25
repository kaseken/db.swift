public class Cursor {
    let btree: BTree
    public var pageNum: UInt32
    public var cellNum: UInt32
    public var endOfTable: Bool

    init(btree: BTree, pageNum: UInt32, cellNum: UInt32, endOfTable: Bool) {
        self.btree = btree
        self.pageNum = pageNum
        self.cellNum = cellNum
        self.endOfTable = endOfTable
    }

    func value() -> (pageIndex: Int, byteOffset: Int) {
        (Int(pageNum), LeafNode.valueOffset(cellNum: Int(cellNum)))
    }

    func advance() {
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
