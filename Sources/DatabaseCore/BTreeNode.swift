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

func nodeType(_ data: Data) -> NodeType {
    NodeType(rawValue: data[BTreeNodeLayout.nodeTypeOffset])!
}

// MARK: - BTreeNode protocol

protocol BTreeNode {
    var nodeType: NodeType { get }
    var isRoot: Bool { get set }
    var parentPageNum: UInt32 { get set }
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
    var parentPageNum: UInt32
    var nextLeafPageNum: UInt32
    /// Stored cells. Each element holds a row key and its serialized Row value.
    var cells: [(key: UInt32, value: Data)]

    // MARK: On-disk layout constants

    /// Alias kept for the `.constants` REPL command output.
    static let commonNodeHeaderSize = BTreeNodeLayout.headerSize

    private static let numCellsSize = 4
    private static let numCellsOffset = BTreeNodeLayout.headerSize // 6
    private static let nextLeafPageNumSize = 4
    private static let nextLeafPageNumOffset = numCellsOffset + numCellsSize // 10
    static let headerSize = BTreeNodeLayout.headerSize + numCellsSize + nextLeafPageNumSize // 14

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
        parentPageNum = data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: BTreeNodeLayout.parentPointerOffset, as: UInt32.self)
        }
        let numCells = data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: LeafNode.numCellsOffset, as: UInt32.self)
        }
        nextLeafPageNum = data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: LeafNode.nextLeafPageNumOffset, as: UInt32.self)
        }
        cells = (0 ..< Int(numCells)).map { i in
            let key = data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: LeafNode.keyOffset(at: i), as: UInt32.self)
            }
            let valOff = LeafNode.valueOffset(at: i)
            return (key: key, value: Data(data[valOff ..< valOff + Row.size]))
        }
    }

    /// Returns a new, empty leaf node.
    static func makeNew() -> LeafNode {
        LeafNode(isRoot: false, parent: 0, nextLeafPageNum: 0, cells: [])
    }

    private init(isRoot: Bool, parent: UInt32, nextLeafPageNum: UInt32, cells: [(key: UInt32, value: Data)]) {
        self.isRoot = isRoot
        parentPageNum = parent
        self.nextLeafPageNum = nextLeafPageNum
        self.cells = cells
    }

    // MARK: Serialization

    var data: Data {
        var out = Data(count: Pager.pageSize)
        out[BTreeNodeLayout.nodeTypeOffset] = NodeType.leaf.rawValue
        out[BTreeNodeLayout.isRootOffset] = isRoot ? 1 : 0
        withUnsafeBytes(of: parentPageNum) { src in
            out.replaceSubrange(BTreeNodeLayout.parentPointerOffset ..< BTreeNodeLayout.parentPointerOffset + 4, with: src)
        }
        let numCells = UInt32(cells.count)
        withUnsafeBytes(of: numCells) { src in
            out.replaceSubrange(LeafNode.numCellsOffset ..< LeafNode.numCellsOffset + LeafNode.numCellsSize, with: src)
        }
        withUnsafeBytes(of: nextLeafPageNum) { src in
            out.replaceSubrange(LeafNode.nextLeafPageNumOffset ..< LeafNode.nextLeafPageNumOffset + LeafNode.nextLeafPageNumSize, with: src)
        }
        for (i, cell) in cells.enumerated() {
            withUnsafeBytes(of: cell.key) { src in
                let off = LeafNode.keyOffset(at: i)
                out.replaceSubrange(off ..< off + LeafNode.keySize, with: src)
            }
            let valOff = LeafNode.valueOffset(at: i)
            out.replaceSubrange(valOff ..< valOff + Row.size, with: cell.value)
        }
        return out
    }

    // MARK: Cell layout helpers (pure arithmetic — used by Cursor.value() and serialization)

    static func cellOffset(at index: Int) -> Int {
        headerSize + index * cellSize
    }

    static func keyOffset(at index: Int) -> Int {
        cellOffset(at: index)
    }

    static func valueOffset(at index: Int) -> Int {
        cellOffset(at: index) + keySize
    }

    // MARK: Convenience accessors

    func key(at index: Int) -> UInt32 {
        cells[index].key
    }

    mutating func setKey(at index: Int, _ key: UInt32) {
        cells[index].key = key
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
    var parentPageNum: UInt32
    /// Stored cells. Each element holds a child page number and its separator key.
    var cells: [(child: UInt32, key: UInt32)]
    /// Page number of the rightmost child, which holds all keys greater than
    /// the last separator key in `cells`.
    var rightmostChildPageNum: UInt32

    /// Sentinel page number meaning "no page assigned".
    static let invalidPageNum: UInt32 = .max

    // MARK: On-disk layout constants

    private static let numKeysSize = 4
    static let numKeysOffset = BTreeNodeLayout.headerSize // 6
    private static let rightmostChildPageNumSize = 4
    static let rightmostChildPageNumOffset = numKeysOffset + numKeysSize // 10
    static let headerSize = BTreeNodeLayout.headerSize + numKeysSize + rightmostChildPageNumSize // 14

    private static let keySize = 4
    private static let childSize = 4
    static let cellSize = childSize + keySize // 8
    static let maxCells = (Pager.pageSize - headerSize) / cellSize

    // MARK: Initializers

    init(_ data: Data) {
        isRoot = data[BTreeNodeLayout.isRootOffset] != 0
        parentPageNum = data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: BTreeNodeLayout.parentPointerOffset, as: UInt32.self)
        }
        let numKeys = data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: InternalNode.numKeysOffset, as: UInt32.self)
        }
        rightmostChildPageNum = data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: InternalNode.rightmostChildPageNumOffset, as: UInt32.self)
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
        InternalNode(isRoot: false, parent: 0, cells: [], rightmostChildPageNum: InternalNode.invalidPageNum)
    }

    private init(isRoot: Bool, parent: UInt32, cells: [(child: UInt32, key: UInt32)], rightmostChildPageNum: UInt32) {
        self.isRoot = isRoot
        parentPageNum = parent
        self.cells = cells
        self.rightmostChildPageNum = rightmostChildPageNum
    }

    // MARK: Serialization

    var data: Data {
        var out = Data(count: Pager.pageSize)
        out[BTreeNodeLayout.nodeTypeOffset] = NodeType.internal.rawValue
        out[BTreeNodeLayout.isRootOffset] = isRoot ? 1 : 0
        withUnsafeBytes(of: parentPageNum) { src in
            out.replaceSubrange(BTreeNodeLayout.parentPointerOffset ..< BTreeNodeLayout.parentPointerOffset + 4, with: src)
        }
        let numKeys = UInt32(cells.count)
        withUnsafeBytes(of: numKeys) { src in
            out.replaceSubrange(InternalNode.numKeysOffset ..< InternalNode.numKeysOffset + InternalNode.numKeysSize, with: src)
        }
        withUnsafeBytes(of: rightmostChildPageNum) { src in
            out.replaceSubrange(InternalNode.rightmostChildPageNumOffset ..< InternalNode.rightmostChildPageNumOffset + InternalNode.rightmostChildPageNumSize, with: src)
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

    private static func cellOffset(cellNum: Int) -> Int {
        headerSize + cellNum * cellSize
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

    func childPageNum(at index: Int) -> UInt32 {
        index == cells.count ? rightmostChildPageNum : cells[index].child
    }

    func key(at index: Int) -> UInt32 {
        cells[index].key
    }

    mutating func setKey(at index: Int, _ key: UInt32) {
        cells[index].key = key
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
