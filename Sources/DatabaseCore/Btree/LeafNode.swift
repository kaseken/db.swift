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

    var parentPageNum: UInt32?
    let pageNum: UInt32
    var nextLeafPageNum: UInt32
    /// Stored cells. Each element holds a row key and its serialized Row value.
    var cells: [(key: UInt32, value: Data)]

    // MARK: On-disk layout constants

    private static let numCellsSize = 4
    private static let numCellsOffset = BTreeNodeLayout.headerSize // 6
    private static let nextLeafPageNumSize = 4
    private static let nextLeafPageNumOffset = numCellsOffset + numCellsSize // 10
    private static let headerSize = BTreeNodeLayout.headerSize + numCellsSize + nextLeafPageNumSize // 14

    private static let keySize = 4
    private static let valueSize = Row.size
    private static let cellSize = keySize + valueSize
    private static let spaceForCells = Pager.pageSize - headerSize
    static let maxCells = spaceForCells / cellSize

    /// Number of cells placed in the new right node after a leaf split.
    private static let rightSplitCount = (maxCells + 1) / 2
    /// Number of cells kept in the existing left node after a leaf split.
    static let leftSplitCount = (maxCells + 1) - rightSplitCount

    init(pageNum: UInt32, parentPageNum: UInt32?,
         nextLeafPageNum: UInt32, cells: [(key: UInt32, value: Data)])
    {
        self.pageNum = pageNum
        self.parentPageNum = parentPageNum
        self.nextLeafPageNum = nextLeafPageNum
        self.cells = cells
    }

    /// Restore from an already-allocated page.
    static func restore(from page: Page) -> LeafNode {
        let isRoot = page.data[BTreeNodeLayout.isRootOffset] != 0
        let rawParentPageNum = page.data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: BTreeNodeLayout.parentPointerOffset, as: UInt32.self)
        }
        let parentPageNum: UInt32? = isRoot ? nil : rawParentPageNum
        let numCells = page.data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: LeafNode.numCellsOffset, as: UInt32.self)
        }
        let nextLeafPageNum = page.data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: LeafNode.nextLeafPageNumOffset, as: UInt32.self)
        }
        let cells = (0 ..< Int(numCells)).map { i in
            let key = page.data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: LeafNode.keyOffset(at: i), as: UInt32.self)
            }
            let valOff = LeafNode.valueOffset(at: i)
            return (key: key, value: Data(page.data[valOff ..< valOff + Row.size]))
        }
        return LeafNode(pageNum: page.pageNum, parentPageNum: parentPageNum,
                        nextLeafPageNum: nextLeafPageNum, cells: cells)
    }

    // MARK: Serialization

    var data: Data {
        var out = Data(count: Pager.pageSize)
        out[BTreeNodeLayout.nodeTypeOffset] = NodeType.leaf.rawValue
        out[BTreeNodeLayout.isRootOffset] = parentPageNum == nil ? 1 : 0
        withUnsafeBytes(of: parentPageNum ?? 0) { src in
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

    private static func cellOffset(at cellNum: Int) -> Int {
        headerSize + cellNum * cellSize
    }

    private static func keyOffset(at cellNum: Int) -> Int {
        cellOffset(at: cellNum)
    }

    private static func valueOffset(at cellNum: Int) -> Int {
        cellOffset(at: cellNum) + keySize
    }

    /// Returns the first cell position where `cells[cellNum].key >= key`,
    /// or `cells.count` (with `endOfTable: true`) if all keys are smaller.
    private func lowerBound(for key: UInt32) -> (cellNum: Int, endOfTable: Bool) {
        var lo = 0
        var hi = cells.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if self.key(at: mid) >= key {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        return (hi, hi >= cells.count)
    }

    func insertionPoint(for key: UInt32) -> Cursor {
        let (cellNum, endOfTable) = lowerBound(for: key)
        return Cursor(node: self, cellNum: UInt32(cellNum), endOfTable: endOfTable)
    }

    func key(at cellNum: Int) -> UInt32 {
        cells[cellNum].key
    }

    var maxKey: UInt32 {
        cells.last!.key
    }
}
