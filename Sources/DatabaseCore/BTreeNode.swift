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

    // Split count constants
    static let rightSplitCount = (maxCells + 1) / 2 // 7
    static let leftSplitCount = (maxCells + 1) - rightSplitCount // 7

    /// Returns a zero-initialized page with node_type set to leaf and isRoot set to false.
    static func initialize() -> Data {
        var page = Data(count: Pager.pageSize)
        page[nodeTypeOffset] = NodeType.leaf.rawValue
        page[isRootOffset] = 0
        // numCells is already 0 from zero-initialized Data
        return page
    }

    static func nodeType(_ page: Data) -> NodeType {
        NodeType(rawValue: page[nodeTypeOffset])!
    }

    static func isRoot(_ page: Data) -> Bool {
        page[isRootOffset] != 0
    }

    static func setIsRoot(_ page: inout Data, _ value: Bool) {
        page[isRootOffset] = value ? 1 : 0
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

/// Namespace for the internal node page format.
///
/// Each page is laid out as follows:
///
///     ┌──────────────────────────────────────┐
///     │ common node header (6 bytes)         │
///     ├──────────────────────────────────────┤
///     │ internal node header (8 bytes)       │
///     │   num_keys    (4) offset 6           │
///     │   right_child (4) offset 10          │
///     ├──────────────────────────────────────┤
///     │ cell 0 (8 bytes)                     │
///     │   child (4) offset 14                │
///     │   key   (4) offset 18                │
///     ├──────────────────────────────────────┤
///     │ cell 1 (8 bytes) ...                 │
///     └──────────────────────────────────────┘
enum InternalNode {
    static let numKeysSize = 4
    static let numKeysOffset = LeafNode.commonNodeHeaderSize // 6
    static let rightChildSize = 4
    static let rightChildOffset = numKeysOffset + numKeysSize // 10
    static let headerSize = LeafNode.commonNodeHeaderSize
        + numKeysSize + rightChildSize // 14

    static let keySize = 4
    static let childSize = 4
    static let cellSize = childSize + keySize // 8

    /// Returns a zero-initialized page with node_type set to internal and isRoot set to false.
    static func initialize() -> Data {
        var page = Data(count: Pager.pageSize)
        page[LeafNode.nodeTypeOffset] = NodeType.internal.rawValue
        page[LeafNode.isRootOffset] = 0
        // numKeys is already 0 from zero-initialized Data
        return page
    }

    static func numKeys(_ page: Data) -> UInt32 {
        page.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: numKeysOffset, as: UInt32.self)
        }
    }

    static func setNumKeys(_ page: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value) { src in
            page.replaceSubrange(numKeysOffset ..< numKeysOffset + numKeysSize, with: src)
        }
    }

    static func rightChild(_ page: Data) -> UInt32 {
        page.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: rightChildOffset, as: UInt32.self)
        }
    }

    static func setRightChild(_ page: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value) { src in
            page.replaceSubrange(rightChildOffset ..< rightChildOffset + rightChildSize, with: src)
        }
    }

    static func cellOffset(cellNum: Int) -> Int {
        headerSize + cellNum * cellSize
    }

    /// Returns the child page number for `childNum`.
    /// When `childNum == numKeys`, returns the right child.
    static func child(_ page: Data, childNum: Int) -> UInt32 {
        let nKeys = numKeys(page)
        precondition(childNum <= Int(nKeys), "Tried to access child_num \(childNum) > num_keys \(nKeys)")
        if childNum == Int(nKeys) {
            return rightChild(page)
        }
        let off = cellOffset(cellNum: childNum)
        return page.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: off, as: UInt32.self)
        }
    }

    static func setChild(_ page: inout Data, childNum: Int, _ value: UInt32) {
        let nKeys = numKeys(page)
        precondition(childNum <= Int(nKeys), "Tried to access child_num \(childNum) > num_keys \(nKeys)")
        if childNum == Int(nKeys) {
            setRightChild(&page, value)
            return
        }
        let off = cellOffset(cellNum: childNum)
        withUnsafeBytes(of: value) { src in
            page.replaceSubrange(off ..< off + childSize, with: src)
        }
    }

    static func keyOffset(keyNum: Int) -> Int {
        cellOffset(cellNum: keyNum) + childSize
    }

    static func key(_ page: Data, keyNum: Int) -> UInt32 {
        let off = keyOffset(keyNum: keyNum)
        return page.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: off, as: UInt32.self)
        }
    }

    static func setKey(_ page: inout Data, keyNum: Int, _ value: UInt32) {
        let off = keyOffset(keyNum: keyNum)
        withUnsafeBytes(of: value) { src in
            page.replaceSubrange(off ..< off + keySize, with: src)
        }
    }
}

func getNodeMaxKey(_ page: Data) -> UInt32 {
    switch LeafNode.nodeType(page) {
    case .leaf:
        LeafNode.key(page, cellNum: Int(LeafNode.numCells(page)) - 1)
    case .internal:
        InternalNode.key(page, keyNum: Int(InternalNode.numKeys(page)) - 1)
    }
}
