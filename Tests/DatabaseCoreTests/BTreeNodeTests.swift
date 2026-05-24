@testable import DatabaseCore
import Testing

struct BTreeNodeTests {
    // MARK: - Constants

    @Test func `constants are correct`() {
        #expect(LeafNode.commonNodeHeaderSize == 6)
        #expect(LeafNode.headerSize == 10)
        #expect(LeafNode.keySize == 4)
        #expect(LeafNode.valueSize == 291)
        #expect(LeafNode.cellSize == 295)
        #expect(LeafNode.spaceForCells == 4086)
        #expect(LeafNode.maxCells == 13)
    }

    // MARK: - initialize

    @Test func `initialize sets node type to leaf`() {
        let page = LeafNode.initialize()
        #expect(page[BTreeNode.nodeTypeOffset] == NodeType.leaf.rawValue)
    }

    @Test func `initialize sets numCells to zero`() {
        let page = LeafNode.initialize()
        #expect(LeafNode.numCells(page) == 0)
    }

    @Test func `initialize returns a full page`() {
        let page = LeafNode.initialize()
        #expect(page.count == Pager.pageSize)
    }

    // MARK: - numCells / setNumCells

    @Test func `setNumCells and numCells round-trip`() {
        var page = LeafNode.initialize()
        LeafNode.setNumCells(&page, 7)
        #expect(LeafNode.numCells(page) == 7)
    }

    @Test func `setNumCells to max`() {
        var page = LeafNode.initialize()
        LeafNode.setNumCells(&page, UInt32(LeafNode.maxCells))
        #expect(LeafNode.numCells(page) == UInt32(LeafNode.maxCells))
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

    @Test func `setKey and key round-trip`() {
        var page = LeafNode.initialize()
        LeafNode.setKey(&page, cellNum: 0, key: 42)
        #expect(LeafNode.key(page, cellNum: 0) == 42)
    }

    @Test func `setKey does not affect other cells`() {
        var page = LeafNode.initialize()
        LeafNode.setKey(&page, cellNum: 0, key: 1)
        LeafNode.setKey(&page, cellNum: 1, key: 2)
        LeafNode.setKey(&page, cellNum: 2, key: 3)
        #expect(LeafNode.key(page, cellNum: 0) == 1)
        #expect(LeafNode.key(page, cellNum: 1) == 2)
        #expect(LeafNode.key(page, cellNum: 2) == 3)
    }

    @Test func `setKey on last cell`() {
        var page = LeafNode.initialize()
        LeafNode.setKey(&page, cellNum: LeafNode.maxCells - 1, key: 999)
        #expect(LeafNode.key(page, cellNum: LeafNode.maxCells - 1) == 999)
    }

    // MARK: - BTreeNode.isRoot

    @Test func `isRoot defaults to false after initialize`() {
        let page = LeafNode.initialize()
        #expect(BTreeNode.isRoot(page) == false)
    }

    @Test func `setIsRoot round-trip`() {
        var page = LeafNode.initialize()
        BTreeNode.setIsRoot(&page, true)
        #expect(BTreeNode.isRoot(page) == true)
        BTreeNode.setIsRoot(&page, false)
        #expect(BTreeNode.isRoot(page) == false)
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

    // MARK: - initialize

    @Test func `InternalNode initialize sets node type to internal`() {
        let page = InternalNode.initialize()
        #expect(page[BTreeNode.nodeTypeOffset] == NodeType.internal.rawValue)
    }

    @Test func `InternalNode initialize sets isRoot to false`() {
        let page = InternalNode.initialize()
        #expect(BTreeNode.isRoot(page) == false)
    }

    @Test func `InternalNode initialize sets numKeys to zero`() {
        let page = InternalNode.initialize()
        #expect(InternalNode.numKeys(page) == 0)
    }

    @Test func `InternalNode initialize returns a full page`() {
        let page = InternalNode.initialize()
        #expect(page.count == Pager.pageSize)
    }

    // MARK: - numKeys / setNumKeys

    @Test func `InternalNode setNumKeys and numKeys round-trip`() {
        var page = InternalNode.initialize()
        InternalNode.setNumKeys(&page, 5)
        #expect(InternalNode.numKeys(page) == 5)
    }

    // MARK: - rightChild / setRightChild

    @Test func `InternalNode setRightChild and rightChild round-trip`() {
        var page = InternalNode.initialize()
        InternalNode.setRightChild(&page, 42)
        #expect(InternalNode.rightChild(page) == 42)
    }

    // MARK: - key / setKey

    @Test func `InternalNode setKey and key round-trip`() {
        var page = InternalNode.initialize()
        InternalNode.setNumKeys(&page, 3)
        InternalNode.setKey(&page, keyNum: 0, 100)
        InternalNode.setKey(&page, keyNum: 1, 200)
        InternalNode.setKey(&page, keyNum: 2, 300)
        #expect(InternalNode.key(page, keyNum: 0) == 100)
        #expect(InternalNode.key(page, keyNum: 1) == 200)
        #expect(InternalNode.key(page, keyNum: 2) == 300)
    }

    // MARK: - child / setChild

    @Test func `InternalNode setChild and child round-trip for internal cells`() {
        var page = InternalNode.initialize()
        InternalNode.setNumKeys(&page, 2)
        InternalNode.setChild(&page, childNum: 0, 10)
        InternalNode.setChild(&page, childNum: 1, 20)
        #expect(InternalNode.child(page, childNum: 0) == 10)
        #expect(InternalNode.child(page, childNum: 1) == 20)
    }

    @Test func `InternalNode setChild with childNum == numKeys sets rightChild`() {
        var page = InternalNode.initialize()
        InternalNode.setNumKeys(&page, 1)
        InternalNode.setChild(&page, childNum: 1, 99)
        #expect(InternalNode.rightChild(page) == 99)
        #expect(InternalNode.child(page, childNum: 1) == 99)
    }
}

// MARK: - getNodeMaxKey

struct GetNodeMaxKeyTests {
    @Test func `getNodeMaxKey on leaf page`() {
        var page = LeafNode.initialize()
        LeafNode.setNumCells(&page, 3)
        LeafNode.setKey(&page, cellNum: 0, key: 10)
        LeafNode.setKey(&page, cellNum: 1, key: 20)
        LeafNode.setKey(&page, cellNum: 2, key: 30)
        #expect(getNodeMaxKey(page) == 30)
    }

    @Test func `getNodeMaxKey on internal page`() {
        var page = InternalNode.initialize()
        InternalNode.setNumKeys(&page, 2)
        InternalNode.setKey(&page, keyNum: 0, 50)
        InternalNode.setKey(&page, keyNum: 1, 100)
        #expect(getNodeMaxKey(page) == 100)
    }
}
