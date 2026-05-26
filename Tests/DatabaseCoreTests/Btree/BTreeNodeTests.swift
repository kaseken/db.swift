@testable import DatabaseCore
import Foundation
import Testing

// MARK: - Test helpers

private extension LeafNode {
    /// Convenience for tests that only need a blank leaf with no pager.
    static func makeNew() -> LeafNode {
        LeafNode(pageNum: 0)
    }
}

private extension InternalNode {
    /// Convenience for tests that only need a blank internal node with no pager.
    static func makeNew() -> InternalNode {
        InternalNode(pageNum: 0)
    }
}

struct BTreeNodeTests {
    // MARK: - Constants

    @Test func `constants are correct`() {
        #expect(LeafNode.commonNodeHeaderSize == 6)
        #expect(LeafNode.headerSize == 14)
        #expect(LeafNode.keySize == 4)
        #expect(LeafNode.valueSize == 291)
        #expect(LeafNode.cellSize == 295)
        #expect(LeafNode.spaceForCells == 4082)
        #expect(LeafNode.maxCells == 13)
    }

    // MARK: - makeNew

    @Test func `makeNew sets node type to leaf`() {
        let node = LeafNode.makeNew()
        #expect(node.nodeType == .leaf)
    }

    @Test func `makeNew returns empty cells`() {
        let node = LeafNode.makeNew()
        #expect(node.cells.isEmpty)
    }

    @Test func `makeNew returns a full page`() {
        let node = LeafNode.makeNew()
        #expect(node.data.count == Pager.pageSize)
    }

    // MARK: - cells

    @Test func `cells count reflects appended cells`() {
        var node = LeafNode.makeNew()
        #expect(node.cells.count == 0)
        for i: UInt32 in 1 ... 7 {
            node.cells.append((key: i, value: Data(count: Row.size)))
        }
        #expect(node.cells.count == 7)
    }

    // MARK: - Offsets

    @Test func `cellOffset for cell 0 starts after header`() {
        #expect(LeafNode.cellOffset(at: 0) == LeafNode.headerSize)
    }

    @Test func `cellOffset increments by cellSize`() {
        #expect(LeafNode.cellOffset(at: 1) == LeafNode.headerSize + LeafNode.cellSize)
        #expect(LeafNode.cellOffset(at: 2) == LeafNode.headerSize + 2 * LeafNode.cellSize)
    }

    @Test func `keyOffset equals cellOffset`() {
        for i in 0 ..< LeafNode.maxCells {
            #expect(LeafNode.keyOffset(at: i) == LeafNode.cellOffset(at: i))
        }
    }

    @Test func `valueOffset is keyOffset plus keySize`() {
        for i in 0 ..< LeafNode.maxCells {
            #expect(LeafNode.valueOffset(at: i) == LeafNode.keyOffset(at: i) + LeafNode.keySize)
        }
    }

    @Test func `last cell fits within page`() {
        let lastCellEnd = LeafNode.cellOffset(at: LeafNode.maxCells - 1) + LeafNode.cellSize
        #expect(lastCellEnd <= Pager.pageSize)
    }

    // MARK: - key / setKey

    @Test func `key round-trip`() {
        var node = LeafNode.makeNew()
        node.cells.append((key: 42, value: Data(count: Row.size)))
        #expect(node.key(at: 0) == 42)
        node.setKey(at: 0, 99)
        #expect(node.key(at: 0) == 99)
    }

    @Test func `setKey does not affect other cells`() {
        var node = LeafNode.makeNew()
        for _ in 0 ..< 3 {
            node.cells.append((key: 0, value: Data(count: Row.size)))
        }
        node.setKey(at: 0, 1)
        node.setKey(at: 1, 2)
        node.setKey(at: 2, 3)
        #expect(node.key(at: 0) == 1)
        #expect(node.key(at: 1) == 2)
        #expect(node.key(at: 2) == 3)
    }

    @Test func `setKey on last cell`() {
        var node = LeafNode.makeNew()
        for i: UInt32 in 0 ..< UInt32(LeafNode.maxCells) {
            node.cells.append((key: i, value: Data(count: Row.size)))
        }
        node.setKey(at: LeafNode.maxCells - 1, 999)
        #expect(node.key(at: LeafNode.maxCells - 1) == 999)
    }

    // MARK: - isRoot

    @Test func `isRoot defaults to false after makeNew`() {
        let node = LeafNode.makeNew()
        #expect(node.isRoot == false)
    }

    @Test func `isRoot round-trip`() {
        var node = LeafNode.makeNew()
        node.isRoot = true
        #expect(node.isRoot == true)
        node.isRoot = false
        #expect(node.isRoot == false)
    }

    // MARK: - Serialization round-trip

    @Test func `data round-trip preserves cells`() {
        var node = LeafNode.makeNew()
        node.isRoot = true
        node.cells = [
            (key: 10, value: Data(repeating: 0xAB, count: Row.size)),
            (key: 20, value: Data(repeating: 0xCD, count: Row.size)),
        ]
        node.nextLeafPageNum = 7
        let restored = LeafNode.restore(from: Page(pageNum: node.pageNum, data: node.data))
        #expect(restored.isRoot == true)
        #expect(restored.nextLeafPageNum == 7)
        #expect(restored.cells.count == 2)
        #expect(restored.cells[0].key == 10)
        #expect(restored.cells[1].key == 20)
    }

    // MARK: - Split count constants

    @Test func `split count constants`() {
        #expect(LeafNode.rightSplitCount == 7)
        #expect(LeafNode.leftSplitCount == 7)
    }
}

struct InternalNodeTests {
    // MARK: - Constants

    @Test func `InternalNode constants are correct`() {
        #expect(InternalNode.numKeysOffset == 6)
        #expect(InternalNode.rightmostChildPageNumOffset == 10)
        #expect(InternalNode.headerSize == 14)
        #expect(InternalNode.cellSize == 8)
    }

    // MARK: - makeNew

    @Test func `InternalNode makeNew sets node type to internal`() {
        let node = InternalNode.makeNew()
        #expect(node.nodeType == .internal)
    }

    @Test func `InternalNode makeNew sets isRoot to false`() {
        let node = InternalNode.makeNew()
        #expect(node.isRoot == false)
    }

    @Test func `InternalNode makeNew returns empty cells`() {
        let node = InternalNode.makeNew()
        #expect(node.cells.isEmpty)
    }

    @Test func `InternalNode makeNew returns a full page`() {
        let node = InternalNode.makeNew()
        #expect(node.data.count == Pager.pageSize)
    }

    // MARK: - cells count

    @Test func `InternalNode cells count reflects appended cells`() {
        var node = InternalNode.makeNew()
        #expect(node.cells.count == 0)
        node.cells.append((child: 1, key: 100))
        node.cells.append((child: 2, key: 200))
        #expect(node.cells.count == 2)
    }

    // MARK: - rightmostChildPageNum

    @Test func `InternalNode rightmostChildPageNum round-trip`() {
        var node = InternalNode.makeNew()
        node.rightmostChildPageNum = 42
        #expect(node.rightmostChildPageNum == 42)
    }

    // MARK: - key / setKey

    @Test func `InternalNode key round-trip`() {
        var node = InternalNode.makeNew()
        node.cells = [(child: 0, key: 100), (child: 0, key: 200), (child: 0, key: 300)]
        #expect(node.key(at: 0) == 100)
        #expect(node.key(at: 1) == 200)
        #expect(node.key(at: 2) == 300)
        node.setKey(at: 1, 250)
        #expect(node.key(at: 1) == 250)
    }

    // MARK: - child / setChild

    @Test func `InternalNode child round-trip for internal cells`() {
        var node = InternalNode.makeNew()
        node.cells = [(child: 10, key: 0), (child: 20, key: 0)]
        #expect(node.childPageNum(at: 0) == 10)
        #expect(node.childPageNum(at: 1) == 20)
    }

    // MARK: - Serialization round-trip

    @Test func `InternalNode data round-trip preserves cells`() {
        var node = InternalNode.makeNew()
        node.isRoot = true
        node.cells = [(child: 3, key: 50), (child: 4, key: 100)]
        node.rightmostChildPageNum = 5
        let restored = InternalNode.restore(from: Page(pageNum: node.pageNum, data: node.data))
        #expect(restored.isRoot == true)
        #expect(restored.cells.count == 2)
        #expect(restored.cells[0].child == 3)
        #expect(restored.cells[0].key == 50)
        #expect(restored.cells[1].key == 100)
        #expect(restored.rightmostChildPageNum == 5)
    }
}

// MARK: - maxKey

struct NodeMaxKeyTests {
    @Test func `maxKey on leaf`() {
        var node = LeafNode.makeNew()
        node.cells = [
            (key: 10, value: Data(count: Row.size)),
            (key: 20, value: Data(count: Row.size)),
            (key: 30, value: Data(count: Row.size)),
        ]
        #expect(node.maxKey == 30)
    }

    @Test func `maxKey on internal`() {
        var node = InternalNode.makeNew()
        node.cells = [(child: 0, key: 50), (child: 0, key: 100)]
        #expect(node.maxKey == 100)
    }
}
