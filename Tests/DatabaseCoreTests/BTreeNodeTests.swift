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
        #expect(page[LeafNode.nodeTypeOffset] == NodeType.leaf.rawValue)
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
}
