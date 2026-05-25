import Foundation

enum NodeType: UInt8 {
    case `internal` = 0
    case leaf = 1
}

/// Byte offsets and sizes of the common node header.
/// Private to this file — consumers work through typed node instances.
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
    var nodeType: NodeType { get }
    var isRoot: Bool { get set }
    var parent: UInt32 { get set }
    /// Serialized page representation, ready to write to the Pager.
    var data: Data { get }
    init(_ data: Data)
}

// MARK: - LeafNode

/// A leaf node page.
///
/// On disk layout:
///
///     ┌──────────────────────────────────────┐
///     │ common node header (6 bytes)         │
///     ├──────────────────────────────────────┤
///     │ leaf node header (8 bytes)           │
///     │   num_cells     (4) offset 6         │
///     │   next_leaf     (4) offset 10        │
///     ├──────────────────────────────────────┤
///     │ cell 0  (295 bytes): key + Row       │
///     │ ...                                  │
///     └──────────────────────────────────────┘
struct LeafNode: BTreeNode {
    var nodeType: NodeType {
        .leaf
    }

    var isRoot: Bool
    var parent: UInt32
    var nextLeaf: UInt32
    /// Stored cells. Each element holds a row key and its serialized Row value.
    var cells: [(key: UInt32, value: Data)]

    // MARK: On-disk layout constants

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

    // MARK: Initializers

    init(_ data: Data) {
        isRoot = data[BTreeNodeLayout.isRootOffset] != 0
        parent = data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: BTreeNodeLayout.parentPointerOffset, as: UInt32.self)
        }
        let numCells = data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: LeafNode.numCellsOffset, as: UInt32.self)
        }
        nextLeaf = data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: LeafNode.nextLeafOffset, as: UInt32.self)
        }
        cells = (0 ..< Int(numCells)).map { i in
            let key = data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: LeafNode.keyOffset(cellNum: i), as: UInt32.self)
            }
            let valOff = LeafNode.valueOffset(cellNum: i)
            return (key: key, value: Data(data[valOff ..< valOff + Row.size]))
        }
    }

    /// Returns a new, empty leaf node.
    static func makeNew() -> LeafNode {
        LeafNode(isRoot: false, parent: 0, nextLeaf: 0, cells: [])
    }

    private init(isRoot: Bool, parent: UInt32, nextLeaf: UInt32, cells: [(key: UInt32, value: Data)]) {
        self.isRoot = isRoot
        self.parent = parent
        self.nextLeaf = nextLeaf
        self.cells = cells
    }

    // MARK: Serialization

    var data: Data {
        var out = Data(count: Pager.pageSize)
        out[BTreeNodeLayout.nodeTypeOffset] = NodeType.leaf.rawValue
        out[BTreeNodeLayout.isRootOffset] = isRoot ? 1 : 0
        withUnsafeBytes(of: parent) { src in
            out.replaceSubrange(BTreeNodeLayout.parentPointerOffset ..< BTreeNodeLayout.parentPointerOffset + 4, with: src)
        }
        let numCells = UInt32(cells.count)
        withUnsafeBytes(of: numCells) { src in
            out.replaceSubrange(LeafNode.numCellsOffset ..< LeafNode.numCellsOffset + LeafNode.numCellsSize, with: src)
        }
        withUnsafeBytes(of: nextLeaf) { src in
            out.replaceSubrange(LeafNode.nextLeafOffset ..< LeafNode.nextLeafOffset + LeafNode.nextLeafSize, with: src)
        }
        for (i, cell) in cells.enumerated() {
            withUnsafeBytes(of: cell.key) { src in
                let off = LeafNode.keyOffset(cellNum: i)
                out.replaceSubrange(off ..< off + LeafNode.keySize, with: src)
            }
            let valOff = LeafNode.valueOffset(cellNum: i)
            out.replaceSubrange(valOff ..< valOff + Row.size, with: cell.value)
        }
        return out
    }

    // MARK: Cell layout helpers (pure arithmetic — used by Cursor.value() and serialization)

    static func cellOffset(cellNum: Int) -> Int {
        headerSize + cellNum * cellSize
    }

    static func keyOffset(cellNum: Int) -> Int {
        cellOffset(cellNum: cellNum)
    }

    static func valueOffset(cellNum: Int) -> Int {
        cellOffset(cellNum: cellNum) + keySize
    }

    // MARK: Convenience accessors

    func key(cellNum: Int) -> UInt32 {
        cells[cellNum].key
    }

    mutating func setKey(cellNum: Int, key: UInt32) {
        cells[cellNum].key = key
    }

    var maxKey: UInt32 {
        cells.last!.key
    }
}

// MARK: - InternalNode

/// An internal node page.
///
/// On disk layout:
///
///     ┌──────────────────────────────────────┐
///     │ common node header (6 bytes)         │
///     ├──────────────────────────────────────┤
///     │ internal node header (8 bytes)       │
///     │   num_keys    (4) offset 6           │
///     │   right_child (4) offset 10          │
///     ├──────────────────────────────────────┤
///     │ cell 0 (8 bytes): child + key        │
///     │ ...                                  │
///     └──────────────────────────────────────┘
struct InternalNode: BTreeNode {
    var nodeType: NodeType {
        .internal
    }

    var isRoot: Bool
    var parent: UInt32
    /// Stored cells. Each element holds a child page number and its separator key.
    var cells: [(child: UInt32, key: UInt32)]
    var rightChild: UInt32

    /// Sentinel page number meaning "no page assigned".
    static let invalidPageNum: UInt32 = .max

    // MARK: On-disk layout constants

    private static let numKeysSize = 4
    static let numKeysOffset = BTreeNodeLayout.headerSize // 6
    private static let rightChildSize = 4
    static let rightChildOffset = numKeysOffset + numKeysSize // 10
    static let headerSize = BTreeNodeLayout.headerSize + numKeysSize + rightChildSize // 14

    private static let keySize = 4
    private static let childSize = 4
    static let cellSize = childSize + keySize // 8

    // MARK: Initializers

    init(_ data: Data) {
        isRoot = data[BTreeNodeLayout.isRootOffset] != 0
        parent = data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: BTreeNodeLayout.parentPointerOffset, as: UInt32.self)
        }
        let numKeys = data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: InternalNode.numKeysOffset, as: UInt32.self)
        }
        rightChild = data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: InternalNode.rightChildOffset, as: UInt32.self)
        }
        cells = (0 ..< Int(numKeys)).map { i in
            let off = InternalNode.cellOffset(cellNum: i)
            let child = data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: off, as: UInt32.self)
            }
            let key = data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: off + InternalNode.childSize, as: UInt32.self)
            }
            return (child: child, key: key)
        }
    }

    /// Returns a new, empty internal node.
    static func makeNew() -> InternalNode {
        InternalNode(isRoot: false, parent: 0, cells: [], rightChild: InternalNode.invalidPageNum)
    }

    private init(isRoot: Bool, parent: UInt32, cells: [(child: UInt32, key: UInt32)], rightChild: UInt32) {
        self.isRoot = isRoot
        self.parent = parent
        self.cells = cells
        self.rightChild = rightChild
    }

    // MARK: Serialization

    var data: Data {
        var out = Data(count: Pager.pageSize)
        out[BTreeNodeLayout.nodeTypeOffset] = NodeType.internal.rawValue
        out[BTreeNodeLayout.isRootOffset] = isRoot ? 1 : 0
        withUnsafeBytes(of: parent) { src in
            out.replaceSubrange(BTreeNodeLayout.parentPointerOffset ..< BTreeNodeLayout.parentPointerOffset + 4, with: src)
        }
        let numKeys = UInt32(cells.count)
        withUnsafeBytes(of: numKeys) { src in
            out.replaceSubrange(InternalNode.numKeysOffset ..< InternalNode.numKeysOffset + InternalNode.numKeysSize, with: src)
        }
        withUnsafeBytes(of: rightChild) { src in
            out.replaceSubrange(InternalNode.rightChildOffset ..< InternalNode.rightChildOffset + InternalNode.rightChildSize, with: src)
        }
        for (i, cell) in cells.enumerated() {
            let off = InternalNode.cellOffset(cellNum: i)
            withUnsafeBytes(of: cell.child) { src in
                out.replaceSubrange(off ..< off + InternalNode.childSize, with: src)
            }
            withUnsafeBytes(of: cell.key) { src in
                out.replaceSubrange(off + InternalNode.childSize ..< off + InternalNode.cellSize, with: src)
            }
        }
        return out
    }

    // MARK: Cell layout helpers

    static func cellOffset(cellNum: Int) -> Int {
        headerSize + cellNum * cellSize
    }

    static func keyOffset(keyNum: Int) -> Int {
        cellOffset(cellNum: keyNum) + childSize
    }

    // MARK: Convenience accessors

    func findChildIndex(key: UInt32) -> Int {
        var lo = 0, hi = cells.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if cells[mid].key >= key { hi = mid } else { lo = mid + 1 }
        }
        return lo
    }

    func child(childNum: Int) -> UInt32 {
        childNum == cells.count ? rightChild : cells[childNum].child
    }

    mutating func setChild(childNum: Int, _ value: UInt32) {
        if childNum == cells.count { rightChild = value } else { cells[childNum].child = value }
    }

    func key(keyNum: Int) -> UInt32 {
        cells[keyNum].key
    }

    mutating func setKey(keyNum: Int, _ value: UInt32) {
        cells[keyNum].key = value
    }

    var maxKey: UInt32 {
        cells.last!.key
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
