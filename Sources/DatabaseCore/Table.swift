import Foundation

public enum ExecuteResult {
    case success
    case tableFull
}

public class Table {
    static let pageSize = 4096
    static let maxPages = 100
    static let rowsPerPage = pageSize / Row.size // 14
    static let maxRows = rowsPerPage * maxPages // 1400

    private(set) var numRows: UInt32 = 0
    private var pages: [Data?] = Array(repeating: nil, count: Table.maxPages)

    public init() {}

    private func rowSlot(_ rowNum: UInt32) -> (pageIndex: Int, byteOffset: Int) {
        let pageIndex = Int(rowNum) / Table.rowsPerPage
        let rowOffset = Int(rowNum) % Table.rowsPerPage
        return (pageIndex, rowOffset * Row.size)
    }

    public func insert(row: Row) -> ExecuteResult {
        guard numRows < Table.maxRows else { return .tableFull }
        let (pageIndex, byteOffset) = rowSlot(numRows)
        if pages[pageIndex] == nil {
            pages[pageIndex] = Data(count: Table.pageSize)
        }
        let serialized = row.serialize()
        pages[pageIndex]!.replaceSubrange(byteOffset ..< byteOffset + Row.size, with: serialized)
        numRows += 1
        return .success
    }

    public func select() -> [Row] {
        (0 ..< numRows).map { rowNum in
            let (pageIndex, byteOffset) = rowSlot(rowNum)
            let slice = Data(pages[pageIndex]![byteOffset ..< byteOffset + Row.size])
            return Row.deserialize(from: slice)
        }
    }
}
