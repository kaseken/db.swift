import Foundation

enum NodeType: UInt8 {
    case `internal` = 0
    case leaf = 1
}

/// Byte offsets and sizes of the common node header.
/// Private to this file — BTree consumers work through typed node instances.
private enum BTreeNodeLayout {
    static let nodeTypeOffset = 0
    static let isRootOffset = 1
    static let parentPointerOffset = 2
    static let headerSize = 6
}

// MARK: - Raw-Data helpers (module-internal)

//
// Used in BTree.swift when the concrete node type is not statically known
// (e.g., updating a child's parent pointer after a split).

func nodeType(_ data: Data) -> NodeType {
    NodeType(rawValue: data[BTreeNodeLayout.nodeTypeOffset])!
}

func setIsRoot(_ data: inout Data, _ value: Bool) {
    data[BTreeNodeLayout.isRootOffset] = value ? 1 : 0
}

func setParent(_ data: inout Data, _ value: UInt32) {
    withUnsafeBytes(of: value) { src in
        data.replaceSubrange(
            BTreeNodeLayout.parentPointerOffset ..< BTreeNodeLayout.parentPointerOffset + 4,
            with: src,
        )
    }
}

// MARK: - BTreeNode protocol

protocol BTreeNode {
    var data: Data { get set }
}

/// Default implementations for the common 6-byte node header.
extension BTreeNode {
    var nodeType: NodeType {
        NodeType(rawValue: data[BTreeNodeLayout.nodeTypeOffset])!
    }

    var isRoot: Bool {
        get { data[BTreeNodeLayout.isRootOffset] != 0 }
        set { data[BTreeNodeLayout.isRootOffset] = newValue ? 1 : 0 }
    }

    var parent: UInt32 {
        get {
            data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: BTreeNodeLayout.parentPointerOffset, as: UInt32.self)
            }
        }
        set {
            withUnsafeBytes(of: newValue) { src in
                data.replaceSubrange(
                    BTreeNodeLayout.parentPointerOffset ..< BTreeNodeLayout.parentPointerOffset + 4,
                    with: src,
                )
            }
        }
    }
}

// MARK: - LeafNode

/// A leaf node page.
///
/// Each page is laid out as follows:
///
///     ┌──────────────────────────────────────┐
///     │ common node header (6 bytes)         │
///     ├──────────────────────────────────────┤
///     │ leaf node header (8 bytes)           │
///     │   num_cells     (4) offset 6         │
///     │   next_leaf     (4) offset 10        │
///     ├──────────────────────────────────────┤
///     │ cell 0  (295 bytes)                  │
///     │   key   (4)  ← row.id                │
///     │   value (291) ← serialized Row       │
///     ├──────────────────────────────────────┤
///     │ cell 1  (295 bytes)                  │
///     │   ...                                │
///     │ (up to 13 cells)                     │
///     └──────────────────────────────────────┘
struct LeafNode: BTreeNode {
    var data: Data

    init(_ data: Data) {
        self.data = data
    }

    /// Returns a new, zero-initialized leaf node page.
    static func makeNew() -> LeafNode {
        var data = Data(count: Pager.pageSize)
        data[BTreeNodeLayout.nodeTypeOffset] = NodeType.leaf.rawValue
        return LeafNode(data)
    }

    // MARK: Layout constants

    /// Alias kept for the `.constants` REPL command output.
    static let commonNodeHeaderSize = BTreeNodeLayout.headerSize

    private static let numCellsSize = 4
    static let numCellsOffset = BTreeNodeLayout.headerSize // 6
    private static let nextLeafSize = 4
    static let nextLeafOffset = numCellsOffset + numCellsSize // 10
    static let headerSize = BTreeNodeLayout.headerSize + numCellsSize + nextLeafSize // 14

    static let keySize = 4
    static let valueSize = Row.size // 291
    static let cellSize = keySize + valueSize // 295
    static let spaceForCells = Pager.pageSize - headerSize // 4082
    static let maxCells = spaceForCells / cellSize // 13

    static let rightSplitCount = (maxCells + 1) / 2 // 7
    static let leftSplitCount = (maxCells + 1) - rightSplitCount // 7

    // MARK: numCells

    var numCells: UInt32 {
        get {
            data.withUnsafeBytes { ptr in
                // numCellsOffset (6) is not 4-byte aligned, so loadUnaligned is required.
                ptr.baseAddress!.loadUnaligned(fromByteOffset: LeafNode.numCellsOffset, as: UInt32.self)
            }
        }
        set {
            withUnsafeBytes(of: newValue) { src in
                data.replaceSubrange(
                    LeafNode.numCellsOffset ..< LeafNode.numCellsOffset + LeafNode.numCellsSize,
                    with: src,
                )
            }
        }
    }

    // MARK: nextLeaf

    var nextLeaf: UInt32 {
        get {
            data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: LeafNode.nextLeafOffset, as: UInt32.self)
            }
        }
        set {
            withUnsafeBytes(of: newValue) { src in
                data.replaceSubrange(
                    LeafNode.nextLeafOffset ..< LeafNode.nextLeafOffset + LeafNode.nextLeafSize,
                    with: src,
                )
            }
        }
    }

    // MARK: Cell layout helpers (pure arithmetic)

    static func cellOffset(cellNum: Int) -> Int {
        headerSize + cellNum * cellSize
    }

    static func keyOffset(cellNum: Int) -> Int {
        cellOffset(cellNum: cellNum)
    }

    static func valueOffset(cellNum: Int) -> Int {
        cellOffset(cellNum: cellNum) + keySize
    }

    // MARK: key / setKey

    func key(cellNum: Int) -> UInt32 {
        data.withUnsafeBytes { ptr in
            // Cell offsets are not 4-byte aligned, so loadUnaligned is required.
            ptr.baseAddress!.loadUnaligned(fromByteOffset: LeafNode.keyOffset(cellNum: cellNum), as: UInt32.self)
        }
    }

    mutating func setKey(cellNum: Int, key: UInt32) {
        withUnsafeBytes(of: key) { src in
            let off = LeafNode.keyOffset(cellNum: cellNum)
            data.replaceSubrange(off ..< off + LeafNode.keySize, with: src)
        }
    }

    var maxKey: UInt32 {
        key(cellNum: Int(numCells) - 1)
    }
}

// MARK: - InternalNode

/// An internal node page.
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
struct InternalNode: BTreeNode {
    var data: Data

    /// Sentinel page number meaning "no page assigned".
    static let invalidPageNum: UInt32 = .max

    init(_ data: Data) {
        self.data = data
    }

    /// Returns a new, zero-initialized internal node page.
    static func makeNew() -> InternalNode {
        var data = Data(count: Pager.pageSize)
        data[BTreeNodeLayout.nodeTypeOffset] = NodeType.internal.rawValue
        var node = InternalNode(data)
        node.rightChild = InternalNode.invalidPageNum
        return node
    }

    // MARK: Layout constants

    private static let numKeysSize = 4
    static let numKeysOffset = BTreeNodeLayout.headerSize // 6
    private static let rightChildSize = 4
    static let rightChildOffset = numKeysOffset + numKeysSize // 10
    static let headerSize = BTreeNodeLayout.headerSize + numKeysSize + rightChildSize // 14

    private static let keySize = 4
    private static let childSize = 4
    static let cellSize = childSize + keySize // 8

    // MARK: numKeys

    var numKeys: UInt32 {
        get {
            data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: InternalNode.numKeysOffset, as: UInt32.self)
            }
        }
        set {
            withUnsafeBytes(of: newValue) { src in
                data.replaceSubrange(
                    InternalNode.numKeysOffset ..< InternalNode.numKeysOffset + InternalNode.numKeysSize,
                    with: src,
                )
            }
        }
    }

    // MARK: rightChild

    var rightChild: UInt32 {
        get {
            data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: InternalNode.rightChildOffset, as: UInt32.self)
            }
        }
        set {
            withUnsafeBytes(of: newValue) { src in
                data.replaceSubrange(
                    InternalNode.rightChildOffset ..< InternalNode.rightChildOffset + InternalNode.rightChildSize,
                    with: src,
                )
            }
        }
    }

    // MARK: Cell layout helpers

    static func cellOffset(cellNum: Int) -> Int {
        headerSize + cellNum * cellSize
    }

    static func keyOffset(keyNum: Int) -> Int {
        cellOffset(cellNum: keyNum) + childSize
    }

    // MARK: findChildIndex (binary search)

    func findChildIndex(key: UInt32) -> Int {
        var minIndex: UInt32 = 0
        var maxIndex = numKeys
        while minIndex < maxIndex {
            let mid = (minIndex + maxIndex) / 2
            if self.key(keyNum: Int(mid)) >= key { maxIndex = mid }
            else { minIndex = mid + 1 }
        }
        return Int(minIndex)
    }

    // MARK: child / setChild

    /// Returns the child page number for `childNum`.
    /// When `childNum == numKeys`, returns the right child.
    func child(childNum: Int) -> UInt32 {
        precondition(childNum <= Int(numKeys), "Tried to access child_num \(childNum) > num_keys \(numKeys)")
        if childNum == Int(numKeys) { return rightChild }
        return data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(
                fromByteOffset: InternalNode.cellOffset(cellNum: childNum), as: UInt32.self,
            )
        }
    }

    mutating func setChild(childNum: Int, _ value: UInt32) {
        precondition(childNum <= Int(numKeys), "Tried to access child_num \(childNum) > num_keys \(numKeys)")
        if childNum == Int(numKeys) { rightChild = value; return }
        let off = InternalNode.cellOffset(cellNum: childNum)
        withUnsafeBytes(of: value) { src in
            data.replaceSubrange(off ..< off + InternalNode.childSize, with: src)
        }
    }

    // MARK: key / setKey

    func key(keyNum: Int) -> UInt32 {
        let off = InternalNode.keyOffset(keyNum: keyNum)
        return data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: off, as: UInt32.self)
        }
    }

    mutating func setKey(keyNum: Int, _ value: UInt32) {
        let off = InternalNode.keyOffset(keyNum: keyNum)
        withUnsafeBytes(of: value) { src in
            data.replaceSubrange(off ..< off + InternalNode.keySize, with: src)
        }
    }

    var maxKey: UInt32 {
        key(keyNum: Int(numKeys) - 1)
    }
}

// MARK: - nodeMaxKey

/// Returns the maximum key stored directly in a page's key fields (non-recursive).
func nodeMaxKey(_ data: Data) -> UInt32 {
    switch nodeType(data) {
    case .leaf: LeafNode(data).maxKey
    case .internal: InternalNode(data).maxKey
    }
}
