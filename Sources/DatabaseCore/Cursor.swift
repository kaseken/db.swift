public class Cursor {
    let table: Table
    public var rowNum: UInt32
    public var endOfTable: Bool

    init(table: Table, rowNum: UInt32, endOfTable: Bool) {
        self.table = table
        self.rowNum = rowNum
        self.endOfTable = endOfTable
    }

    func value() -> (pageIndex: Int, byteOffset: Int) {
        let pageIndex = Int(rowNum) / Table.rowsPerPage
        let rowOffset = Int(rowNum) % Table.rowsPerPage
        return (pageIndex, rowOffset * Row.size)
    }

    func advance() {
        rowNum += 1
        if rowNum >= table.numRows {
            endOfTable = true
        }
    }
}
