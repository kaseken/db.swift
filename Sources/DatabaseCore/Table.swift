import Foundation

public enum ExecuteError: Error {
    case duplicateKey
    case tableFull
}

public class Table {
    let btree: BTree

    public init(filename: String) throws {
        let pager = try Pager(filename: filename)
        btree = try BTree(pager: pager)
    }

    public func close() {
        btree.close()
    }

    public func execute(_ statement: Statement) throws(ExecuteError) {
        switch statement {
        case let .insert(row):
            try btree.insert(row: row)
        case .select:
            btree.rows.forEach { $0.printRow() }
        }
    }
}
