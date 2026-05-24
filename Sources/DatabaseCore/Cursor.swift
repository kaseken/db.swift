public class Cursor {
    let table: Table
    public var pageNum: UInt32
    public var cellNum: UInt32
    public var endOfTable: Bool

    init(table: Table, pageNum: UInt32, cellNum: UInt32, endOfTable: Bool) {
        self.table = table
        self.pageNum = pageNum
        self.cellNum = cellNum
        self.endOfTable = endOfTable
    }

    func value() -> (pageIndex: Int, byteOffset: Int) {
        (Int(pageNum), LeafNode.valueOffset(cellNum: Int(cellNum)))
    }

    func advance() {
        let node = table.pager.getPage(Int(pageNum))
        cellNum += 1
        if cellNum >= LeafNode.numCells(node) {
            endOfTable = true
        }
    }
}
