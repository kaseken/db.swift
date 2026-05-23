import Foundation

public enum ExecuteResult {
    case success
    case tableFull
}

public class Table {
    // Same size as OS virtual memory pages to maximize I/O efficiency
    static let pageSize = 4096
    static let maxPages = 100
    static let rowsPerPage = pageSize / Row.size // 14
    static let maxRows = rowsPerPage * maxPages // 1400

    private(set) var numRows: UInt32 = 0
    /// Lazy allocation: pages are allocated only on first access
    private var pages: [Data?] = Array(repeating: nil, count: Table.maxPages)

    public init() {}

    /// Returns the page index and byte offset within that page for a given row number
    private func rowSlot(_ rowNum: UInt32) -> (pageIndex: Int, byteOffset: Int) {
        let pageIndex = Int(rowNum) / Table.rowsPerPage
        let rowOffset = Int(rowNum) % Table.rowsPerPage
        return (pageIndex, rowOffset * Row.size)
    }

    public func insert(row: Row) -> ExecuteResult {
        guard numRows < Table.maxRows else { return .tableFull }
        let (pageIndex, byteOffset) = rowSlot(numRows)
        // Allocate a zero-initialized buffer on the first write to this page
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
            // Copy the slice to rebase indices to zero, as Data slices retain parent-based indices
            let slice = Data(pages[pageIndex]![byteOffset ..< byteOffset + Row.size])
            return Row.deserialize(from: slice)
        }
    }
}
