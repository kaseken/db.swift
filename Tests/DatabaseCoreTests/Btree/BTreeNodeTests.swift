@testable import DatabaseCore
import Foundation
import Testing

struct BTreeNodeTests {
    // MARK: - cells

    @Test func `cells count reflects appended cells`() {
        var node = LeafNode(pageNum: 0, parentPageNum: 0, nextLeafPageNum: 0, cells: [])
        #expect(node.cells.count == 0)
        for i: UInt32 in 1 ... 7 {
            node.cells.append((key: i, value: Data(count: Row.size)))
        }
        #expect(node.cells.count == 7)
    }

    // MARK: - parent

    @Test func `parentPageNum defaults to 0`() {
        let node = LeafNode(pageNum: 0, parentPageNum: 0, nextLeafPageNum: 0, cells: [])
        #expect(node.parentPageNum == 0)
    }

    @Test func `parentPageNum round-trip`() {
        var node = LeafNode(pageNum: 0, parentPageNum: nil, nextLeafPageNum: 0, cells: [])
        #expect(node.parentPageNum == nil)
        node.parentPageNum = 5
        #expect(node.parentPageNum == 5)
    }

    // MARK: - Serialization round-trip

    @Test func `data round-trip preserves cells`() {
        let node = LeafNode(pageNum: 0, parentPageNum: nil, nextLeafPageNum: 7, cells: [
            (key: 10, value: Data(repeating: 0xAB, count: Row.size)),
            (key: 20, value: Data(repeating: 0xCD, count: Row.size)),
        ])
        let restored = LeafNode.restore(from: Page(pageNum: node.pageNum, data: node.data))
        #expect(restored.parentPageNum == nil)
        #expect(restored.nextLeafPageNum == 7)
        #expect(restored.cells.count == 2)
        #expect(restored.cells[0].key == 10)
        #expect(restored.cells[1].key == 20)
    }
}

struct InternalNodeTests {
    // MARK: - cells count

    @Test func `InternalNode cells count reflects appended cells`() {
        var node = InternalNode(pageNum: 0, parentPageNum: 0, cells: [], rightmostChildPageNum: nil)
        #expect(node.cells.count == 0)
        node.cells.append((childPageNum: 1, maxKeyInChildPage: 100))
        node.cells.append((childPageNum: 2, maxKeyInChildPage: 200))
        #expect(node.cells.count == 2)
    }

    // MARK: - rightmostChildPageNum

    @Test func `InternalNode rightmostChildPageNum round-trip`() {
        var node = InternalNode(pageNum: 0, parentPageNum: 0, cells: [], rightmostChildPageNum: nil)
        node.rightmostChildPageNum = 42
        #expect(node.rightmostChildPageNum == 42)
    }

    // MARK: - maxKeyInChildPage / setMaxKeyInChildPage

    @Test func `InternalNode maxKeyInChildPage round-trip`() {
        var node = InternalNode(pageNum: 0, parentPageNum: 0, cells: [
            (childPageNum: 0, maxKeyInChildPage: 100),
            (childPageNum: 0, maxKeyInChildPage: 200),
            (childPageNum: 0, maxKeyInChildPage: 300),
        ], rightmostChildPageNum: nil)
        #expect(node.maxKeyInChildPage(at: 0) == 100)
        #expect(node.maxKeyInChildPage(at: 1) == 200)
        #expect(node.maxKeyInChildPage(at: 2) == 300)
        node.setMaxKeyInChildPage(250, at: 1)
        #expect(node.maxKeyInChildPage(at: 1) == 250)
    }

    // MARK: - childPageNum

    @Test func `InternalNode childPageNum round-trip for internal cells`() {
        let node = InternalNode(pageNum: 0, parentPageNum: 0, cells: [(childPageNum: 10, maxKeyInChildPage: 0), (childPageNum: 20, maxKeyInChildPage: 0)], rightmostChildPageNum: nil)
        #expect(node.childPageNum(at: 0) == 10)
        #expect(node.childPageNum(at: 1) == 20)
    }

    // MARK: - Serialization round-trip

    @Test func `InternalNode data round-trip preserves cells`() {
        let node = InternalNode(pageNum: 0, parentPageNum: nil, cells: [
            (childPageNum: 3, maxKeyInChildPage: 50),
            (childPageNum: 4, maxKeyInChildPage: 100),
        ], rightmostChildPageNum: 5)
        let restored = InternalNode.restore(from: Page(pageNum: node.pageNum, data: node.data))
        #expect(restored.parentPageNum == nil)
        #expect(restored.cells.count == 2)
        #expect(restored.cells[0].childPageNum == 3)
        #expect(restored.cells[0].maxKeyInChildPage == 50)
        #expect(restored.cells[1].maxKeyInChildPage == 100)
        #expect(restored.rightmostChildPageNum == 5)
    }
}
