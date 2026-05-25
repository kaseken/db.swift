@testable import DatabaseCore
import Testing

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

    @Test func `makeNew sets numCells to zero`() {
        let node = LeafNode.makeNew()
        #expect(node.numCells == 0)
    }

    @Test func `makeNew returns a full page`() {
        let node = LeafNode.makeNew()
        #expect(node.data.count == Pager.pageSize)
    }

    // MARK: - numCells

    @Test func `numCells round-trip`() {
        var node = LeafNode.makeNew()
        node.numCells = 7
        #expect(node.numCells == 7)
    }

    @Test func `numCells set to max`() {
        var node = LeafNode.makeNew()
        node.numCells = UInt32(LeafNode.maxCells)
        #expect(node.numCells == UInt32(LeafNode.maxCells))
    }

    // MARK: - Offsets

    @Test func `cellOffset for cell 0 starts after header`() {
        #expect(LeafNode.cellOffset(cellNum: 0) == LeafNode.headerSize)
    }

    @Test func `cellOffset increments by cellSize`() {
        #expect(LeafNode.cellOffset(cellNum: 1) == LeafNode.headerSize + LeafNode.cellSize)
        #expect(LeafNode.cellOffset(cellNum: 2) == LeafNode.headerSize + 2 * LeafNode.cellSize)
    }

    @Test func `keyOffset equals cellOffset`() {
        for i in 0 ..< LeafNode.maxCells {
            #expect(LeafNode.keyOffset(cellNum: i) == LeafNode.cellOffset(cellNum: i))
        }
    }

    @Test func `valueOffset is keyOffset plus keySize`() {
        for i in 0 ..< LeafNode.maxCells {
            #expect(LeafNode.valueOffset(cellNum: i) == LeafNode.keyOffset(cellNum: i) + LeafNode.keySize)
        }
    }

    @Test func `last cell fits within page`() {
        let lastCellEnd = LeafNode.cellOffset(cellNum: LeafNode.maxCells - 1) + LeafNode.cellSize
        #expect(lastCellEnd <= Pager.pageSize)
    }

    // MARK: - key / setKey

    @Test func `key round-trip`() {
        var node = LeafNode.makeNew()
        node.setKey(cellNum: 0, key: 42)
        #expect(node.key(cellNum: 0) == 42)
    }

    @Test func `setKey does not affect other cells`() {
        var node = LeafNode.makeNew()
        node.setKey(cellNum: 0, key: 1)
        node.setKey(cellNum: 1, key: 2)
        node.setKey(cellNum: 2, key: 3)
        #expect(node.key(cellNum: 0) == 1)
        #expect(node.key(cellNum: 1) == 2)
        #expect(node.key(cellNum: 2) == 3)
    }

    @Test func `setKey on last cell`() {
        var node = LeafNode.makeNew()
        node.setKey(cellNum: LeafNode.maxCells - 1, key: 999)
        #expect(node.key(cellNum: LeafNode.maxCells - 1) == 999)
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
        #expect(InternalNode.rightChildOffset == 10)
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

    @Test func `InternalNode makeNew sets numKeys to zero`() {
        let node = InternalNode.makeNew()
        #expect(node.numKeys == 0)
    }

    @Test func `InternalNode makeNew returns a full page`() {
        let node = InternalNode.makeNew()
        #expect(node.data.count == Pager.pageSize)
    }

    // MARK: - numKeys

    @Test func `InternalNode numKeys round-trip`() {
        var node = InternalNode.makeNew()
        node.numKeys = 5
        #expect(node.numKeys == 5)
    }

    // MARK: - rightChild

    @Test func `InternalNode rightChild round-trip`() {
        var node = InternalNode.makeNew()
        node.rightChild = 42
        #expect(node.rightChild == 42)
    }

    // MARK: - key / setKey

    @Test func `InternalNode key round-trip`() {
        var node = InternalNode.makeNew()
        node.numKeys = 3
        node.setKey(keyNum: 0, 100)
        node.setKey(keyNum: 1, 200)
        node.setKey(keyNum: 2, 300)
        #expect(node.key(keyNum: 0) == 100)
        #expect(node.key(keyNum: 1) == 200)
        #expect(node.key(keyNum: 2) == 300)
    }

    // MARK: - child / setChild

    @Test func `InternalNode child round-trip for internal cells`() {
        var node = InternalNode.makeNew()
        node.numKeys = 2
        node.setChild(childNum: 0, 10)
        node.setChild(childNum: 1, 20)
        #expect(node.child(childNum: 0) == 10)
        #expect(node.child(childNum: 1) == 20)
    }

    @Test func `InternalNode setChild with childNum == numKeys sets rightChild`() {
        var node = InternalNode.makeNew()
        node.numKeys = 1
        node.setChild(childNum: 1, 99)
        #expect(node.rightChild == 99)
        #expect(node.child(childNum: 1) == 99)
    }
}

// MARK: - nodeMaxKey

struct NodeMaxKeyTests {
    @Test func `nodeMaxKey on leaf`() {
        var node = LeafNode.makeNew()
        node.numCells = 3
        node.setKey(cellNum: 0, key: 10)
        node.setKey(cellNum: 1, key: 20)
        node.setKey(cellNum: 2, key: 30)
        #expect(nodeMaxKey(node.data) == 30)
    }

    @Test func `nodeMaxKey on internal`() {
        var node = InternalNode.makeNew()
        node.numKeys = 2
        node.setKey(keyNum: 0, 50)
        node.setKey(keyNum: 1, 100)
        #expect(nodeMaxKey(node.data) == 100)
    }
}
