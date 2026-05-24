import Foundation

enum NodeType: UInt8 {
    case `internal` = 0
    case leaf = 1
}

/// Namespace for the leaf node page format.
///
/// Each page is laid out as follows:
///
///     ┌──────────────────────────────────────┐
///     │ common node header (6 bytes)         │
///     │   node_type     (1) offset 0         │
///     │   is_root       (1) offset 1         │
///     │   parent_ptr    (4) offset 2         │
///     ├──────────────────────────────────────┤
///     │ leaf node header (4 bytes)           │
///     │   num_cells     (4) offset 6         │
///     ├──────────────────────────────────────┤
///     │ cell 0  (295 bytes)                  │
///     │   key   (4)  ← row.id                │
///     │   value (291) ← serialized Row       │
///     ├──────────────────────────────────────┤
///     │ cell 1  (295 bytes)                  │
///     │   ...                                │
///     │ (up to 13 cells)                     │
///     └──────────────────────────────────────┘
enum LeafNode {
    // Common node header layout
    static let nodeTypeSize = 1
    static let nodeTypeOffset = 0
    static let isRootSize = 1
    static let isRootOffset = 1
    static let parentPointerSize = 4
    static let parentPointerOffset = 2
    static let commonNodeHeaderSize = 6

    // Leaf node header layout
    static let numCellsSize = 4
    static let numCellsOffset = commonNodeHeaderSize
    static let headerSize = commonNodeHeaderSize + numCellsSize // 10

    // Leaf node body layout.
    // A cell is the unit of storage in a leaf node: a key (row.id) followed by a serialized Row.
    static let keySize = 4
    static let valueSize = Row.size // 291
    static let cellSize = keySize + valueSize // 295
    static let spaceForCells = Pager.pageSize - headerSize // 4086
    static let maxCells = spaceForCells / cellSize // 13

    /// Returns a zero-initialized page with node_type set to leaf.
    static func initialize() -> Data {
        var page = Data(count: Pager.pageSize)
        page[nodeTypeOffset] = NodeType.leaf.rawValue
        // numCells is already 0 from zero-initialized Data
        return page
    }

    /// Returns the number of cells stored in the page.
    static func numCells(_ page: Data) -> UInt32 {
        page.withUnsafeBytes { ptr in
            // numCellsOffset (6) is not 4-byte aligned, so loadUnaligned is required.
            ptr.baseAddress!.loadUnaligned(fromByteOffset: numCellsOffset, as: UInt32.self)
        }
    }

    static func setNumCells(_ page: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value) { src in
            page.replaceSubrange(numCellsOffset ..< numCellsOffset + numCellsSize, with: src)
        }
    }

    /// Returns the byte offset of cell `cellNum` within the page.
    static func cellOffset(cellNum: Int) -> Int {
        headerSize + cellNum * cellSize
    }

    /// Returns the byte offset of the key field in cell `cellNum`.
    static func keyOffset(cellNum: Int) -> Int {
        cellOffset(cellNum: cellNum)
    }

    /// Returns the byte offset of the value field (serialized Row) in cell `cellNum`.
    static func valueOffset(cellNum: Int) -> Int {
        cellOffset(cellNum: cellNum) + keySize
    }

    /// Returns the key (row.id) stored in cell `cellNum`.
    static func key(_ page: Data, cellNum: Int) -> UInt32 {
        page.withUnsafeBytes { ptr in
            // Cell offsets are not 4-byte aligned, so loadUnaligned is required.
            ptr.baseAddress!.loadUnaligned(fromByteOffset: keyOffset(cellNum: cellNum), as: UInt32.self)
        }
    }

    static func setKey(_ page: inout Data, cellNum: Int, key: UInt32) {
        withUnsafeBytes(of: key) { src in
            let off = keyOffset(cellNum: cellNum)
            page.replaceSubrange(off ..< off + keySize, with: src)
        }
    }
}
