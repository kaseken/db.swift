import Foundation

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
