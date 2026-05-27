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
    var cells: [(childPageNum: UInt32, maxKeyInChildPage: UInt32)]
    /// Page number of the rightmost child, which holds all keys greater than
    /// the last separator key in `cells`. `nil` when no rightmost child has been assigned yet.
    var rightmostChildPageNum: UInt32?

    // MARK: On-disk layout constants

    private static let numKeysSize = 4
    private static let numKeysOffset = BTreeNodeLayout.headerSize // 6
    private static let rightmostChildPageNumSize = 4
    private static let rightmostChildPageNumOffset = numKeysOffset + numKeysSize // 10
    private static let headerSize = BTreeNodeLayout.headerSize + numKeysSize + rightmostChildPageNumSize // 14

    private static let keySize = 4
    private static let childSize = 4
    private static let cellSize = childSize + keySize // 8
    static let maxCells = (Pager.pageSize - headerSize) / cellSize

    /// On-disk sentinel meaning "no rightmost child assigned".
    private static let noRightmostChild: UInt32 = .max

    // MARK: Initializers

    init(pageNum: UInt32, isRoot: Bool, parentPageNum: UInt32,
         cells: [(childPageNum: UInt32, maxKeyInChildPage: UInt32)],
         rightmostChildPageNum: UInt32?)
    {
        self.pageNum = pageNum
        self.isRoot = isRoot
        self.parentPageNum = parentPageNum
        self.cells = cells
        self.rightmostChildPageNum = rightmostChildPageNum
    }

    /// Restore from an already-allocated page.
    static func restore(from page: Page) -> InternalNode {
        var node = InternalNode(pageNum: page.pageNum, isRoot: false, parentPageNum: 0, cells: [], rightmostChildPageNum: nil)
        node.isRoot = page.data[BTreeNodeLayout.isRootOffset] != 0
        node.parentPageNum = page.data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: BTreeNodeLayout.parentPointerOffset, as: UInt32.self)
        }
        let numKeys = page.data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: InternalNode.numKeysOffset, as: UInt32.self)
        }
        let rawRightmost = page.data.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: InternalNode.rightmostChildPageNumOffset, as: UInt32.self)
        }
        node.rightmostChildPageNum = rawRightmost == Self.noRightmostChild ? nil : rawRightmost
        node.cells = (0 ..< Int(numKeys)).map { i in
            let off = InternalNode.cellOffset(cellNum: i)
            let child = page.data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: off, as: UInt32.self)
            }
            let key = page.data.withUnsafeBytes { ptr in
                ptr.baseAddress!.loadUnaligned(fromByteOffset: off + InternalNode.childSize, as: UInt32.self)
            }
            return (childPageNum: child, maxKeyInChildPage: key)
        }
        return node
    }

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
        withUnsafeBytes(of: rightmostChildPageNum ?? Self.noRightmostChild) { src in
            out.replaceSubrange(InternalNode.rightmostChildPageNumOffset ..< InternalNode.rightmostChildPageNumOffset + InternalNode.rightmostChildPageNumSize, with: src)
        }
        for (i, cell) in cells.enumerated() {
            let off = InternalNode.cellOffset(cellNum: i)
            withUnsafeBytes(of: cell.childPageNum) { src in
                out.replaceSubrange(off ..< off + InternalNode.childSize, with: src)
            }
            withUnsafeBytes(of: cell.maxKeyInChildPage) { src in
                out.replaceSubrange(off + InternalNode.childSize ..< off + InternalNode.cellSize, with: src)
            }
        }
        return out
    }

    private static func cellOffset(cellNum: Int) -> Int {
        headerSize + cellNum * cellSize
    }

    /// Returns the cell number of the child subtree that would contain the given key if it existed.
    func childCellNum(for key: UInt32) -> Int {
        var lo = 0
        var hi = cells.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if cells[mid].maxKeyInChildPage >= key {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        return hi
    }

    func insertionPoint(for key: UInt32, pager: Pager) -> Cursor {
        let childPageNum = childPageNum(at: childCellNum(for: key))!
        return switch BTreeNodeFactory.restore(from: try! pager.getPage(Int(childPageNum))) {
        case let .leaf(node): node.insertionPoint(for: key)
        case let .internal(node): node.insertionPoint(for: key, pager: pager)
        }
    }

    func childPageNum(at cellNum: Int) -> UInt32? {
        cellNum == cells.count ? rightmostChildPageNum : cells[cellNum].childPageNum
    }

    func maxKeyInChildPage(at cellNum: Int) -> UInt32 {
        cells[cellNum].maxKeyInChildPage
    }

    mutating func setMaxKeyInChildPage(_ key: UInt32, at cellNum: Int) {
        cells[cellNum].maxKeyInChildPage = key
    }
}
