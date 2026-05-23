import Foundation

public enum ExecuteResult {
    case success
    case tableFull
}

public class Table {
    static let pageSize = Pager.pageSize
    static let maxPages = Pager.maxPages
    static let rowsPerPage = pageSize / Row.size // 14
    static let maxRows = rowsPerPage * maxPages // 1400

    private(set) var numRows: UInt32
    private let pager: Pager

    public init(filename: String) throws {
        let pager = try Pager(filename: filename)
        self.pager = pager
        let numFullPages = pager.fileLength / Table.pageSize
        let remainingBytes = pager.fileLength % Table.pageSize
        numRows = UInt32(numFullPages * Table.rowsPerPage + remainingBytes / Row.size)
    }

    public func close() {
        let numFullPages = Int(numRows) / Table.rowsPerPage
        let numAdditionalRows = Int(numRows) % Table.rowsPerPage
        let pagesToFlush = numFullPages + (numAdditionalRows > 0 ? 1 : 0)

        for pageNum in 0 ..< pagesToFlush {
            let numBytes: Int = if pageNum == numFullPages, numAdditionalRows > 0 {
                numAdditionalRows * Row.size
            } else {
                Table.pageSize
            }
            pager.flush(pageNum: pageNum, numBytes: numBytes)
        }
        pager.close()
    }

    private func rowSlot(_ rowNum: UInt32) -> (pageIndex: Int, byteOffset: Int) {
        let pageIndex = Int(rowNum) / Table.rowsPerPage
        let rowOffset = Int(rowNum) % Table.rowsPerPage
        return (pageIndex, rowOffset * Row.size)
    }

    @discardableResult
    public func insert(row: Row) -> ExecuteResult {
        guard numRows < Table.maxRows else { return .tableFull }
        let (pageIndex, byteOffset) = rowSlot(numRows)
        var page = pager.getPage(pageIndex)
        let serialized = row.serialize()
        page.replaceSubrange(byteOffset ..< byteOffset + Row.size, with: serialized)
        pager.setPage(pageIndex, data: page)
        numRows += 1
        return .success
    }

    public func select() -> [Row] {
        (0 ..< numRows).map { rowNum in
            let (pageIndex, byteOffset) = rowSlot(rowNum)
            let page = pager.getPage(pageIndex)
            let slice = Data(page[byteOffset ..< byteOffset + Row.size])
            return Row.deserialize(from: slice)
        }
    }
}
