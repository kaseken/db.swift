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
        let numFullPages = pager.diskFileLength / Table.pageSize
        let remainingBytes = pager.diskFileLength % Table.pageSize
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

    func tableStart() -> Cursor {
        Cursor(table: self, rowNum: 0, endOfTable: numRows == 0)
    }

    func tableEnd() -> Cursor {
        Cursor(table: self, rowNum: numRows, endOfTable: true)
    }

    @discardableResult
    public func insert(row: Row) -> ExecuteResult {
        guard numRows < Table.maxRows else {
            return .tableFull
        }
        let cursor = tableEnd()
        let (pageIndex, byteOffset) = cursor.value()
        var page = pager.getPage(pageIndex)
        let serialized = row.serialize()
        page.replaceSubrange(byteOffset ..< byteOffset + Row.size, with: serialized)
        pager.setPage(pageIndex, data: page)
        numRows += 1
        return .success
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
}
