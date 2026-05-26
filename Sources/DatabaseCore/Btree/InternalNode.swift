import Foundation

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
    let pageNum: UInt32
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

    /// Pattern 1: allocate a new page from pager and initialize to defaults.
    init(pager: Pager) throws(PagerError) {
        let page = try pager.allocatePage()
        pageNum = page.pageNum
        isRoot = false
        parentPageNum = 0
        cells = []
        rightmostChildPageNum = InternalNode.invalidPageNum
    }

    /// Pattern 2: restore from an already-allocated page.
    static func restore(from page: Page) -> InternalNode {
        InternalNode(restoring: page)
    }

    /// Internal only — for creating a blank node at a known page (e.g. createNewRoot overwriting page 0).
    init(pageNum: UInt32) {
        self.pageNum = pageNum
        isRoot = false
        parentPageNum = 0
        cells = []
        rightmostChildPageNum = InternalNode.invalidPageNum
    }

    private init(restoring page: Page) {
        pageNum = page.pageNum
        isRoot = page.data[BTreeNodeLayout.isRootOffset] != 0
        parentPageNum = page.data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: BTreeNodeLayout.parentPointerOffset, as: UInt32.self)
        }
        let numKeys = page.data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: InternalNode.numKeysOffset, as: UInt32.self)
        }
        rightmostChildPageNum = page.data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: InternalNode.rightmostChildPageNumOffset, as: UInt32.self)
        }
        cells = (0 ..< Int(numKeys)).map { i in
            let off = InternalNode.cellOffset(cellNum: i)
            let child = page.data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: off, as: UInt32.self)
            }
            let key = page.data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: off + InternalNode.childSize, as: UInt32.self)
            }
            return (child: child, key: key)
        }
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
