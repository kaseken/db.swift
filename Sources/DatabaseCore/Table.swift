import Foundation

public enum ExecuteResult {
    case success
    case duplicateKey
}

public class Table {
    let rootPageNum: UInt32 = 0
    let pager: Pager

    public init(filename: String) throws {
        let pager = try Pager(filename: filename)
        self.pager = pager
        if pager.numPages == 0 {
            var rootPage = pager.getPage(0)
            rootPage = LeafNode.initialize()
            BTreeNode.setIsRoot(&rootPage, true)
            pager.setPage(0, data: rootPage)
        }
    }

    public func close() {
        for i in 0 ..< pager.numPages {
            pager.flush(pageNum: i, numBytes: Pager.pageSize)
        }
        pager.close()
    }

    func tableStart() -> Cursor {
        let page = pager.getPage(Int(rootPageNum))
        let numCells = LeafNode.numCells(page)
        return Cursor(table: self, pageNum: rootPageNum, cellNum: 0, endOfTable: numCells == 0)
    }

    private func leafNodeFind(pageNum: UInt32, key: UInt32) -> Cursor {
        let page = pager.getPage(Int(pageNum))
        let numCells = LeafNode.numCells(page)
        var minIndex: UInt32 = 0
        var onePastMaxIndex = numCells
        while minIndex < onePastMaxIndex {
            let index = (minIndex + onePastMaxIndex) / 2
            let keyAtIndex = LeafNode.key(page, cellNum: Int(index))
            if key == keyAtIndex {
                return Cursor(table: self, pageNum: pageNum, cellNum: index, endOfTable: false)
            }
            if key < keyAtIndex {
                onePastMaxIndex = index
            } else {
                minIndex = index + 1
            }
        }
        return Cursor(table: self, pageNum: pageNum, cellNum: minIndex, endOfTable: minIndex >= numCells)
    }

    func tableFind(key: UInt32) -> Cursor {
        let page = pager.getPage(Int(rootPageNum))
        switch BTreeNode.nodeType(page) {
        case .leaf:
            return leafNodeFind(pageNum: rootPageNum, key: key)
        case .internal:
            print("Need to implement searching an internal node")
            Foundation.exit(1)
        }
    }

    @discardableResult
    public func insert(row: Row) -> ExecuteResult {
        let cursor = tableFind(key: row.id)
        let page = pager.getPage(Int(cursor.pageNum))
        let numCells = LeafNode.numCells(page)
        if cursor.cellNum < numCells {
            let existingKey = LeafNode.key(page, cellNum: Int(cursor.cellNum))
            if existingKey == row.id {
                return .duplicateKey
            }
        }
        leafNodeInsert(cursor: cursor, key: row.id, row: row)
        return .success
    }

    private func leafNodeInsert(cursor: Cursor, key: UInt32, row: Row) {
        var page = pager.getPage(Int(cursor.pageNum))
        let numCells = LeafNode.numCells(page)
        if numCells >= UInt32(LeafNode.maxCells) {
            leafNodeSplitAndInsert(cursor: cursor, key: key, row: row)
            return
        }
        if cursor.cellNum < numCells {
            var i = numCells
            while i > cursor.cellNum {
                let src = LeafNode.cellOffset(cellNum: Int(i) - 1)
                let dst = LeafNode.cellOffset(cellNum: Int(i))
                page.replaceSubrange(dst ..< dst + LeafNode.cellSize, with: page[src ..< src + LeafNode.cellSize])
                i -= 1
            }
        }
        LeafNode.setNumCells(&page, numCells + 1)
        LeafNode.setKey(&page, cellNum: Int(cursor.cellNum), key: key)
        let serialized = row.serialize()
        let valueOff = LeafNode.valueOffset(cellNum: Int(cursor.cellNum))
        page.replaceSubrange(valueOff ..< valueOff + Row.size, with: serialized)
        pager.setPage(Int(cursor.pageNum), data: page)
    }

    private func leafNodeSplitAndInsert(cursor: Cursor, key: UInt32, row: Row) {
        let oldPageCopy = pager.getPage(Int(cursor.pageNum))
        var oldPage = oldPageCopy
        let newPageNum = pager.numPages
        var newPage = LeafNode.initialize()
        BTreeNode.setIsRoot(&newPage, false)

        for i in stride(from: LeafNode.maxCells, through: 0, by: -1) {
            let destIsNew = i >= LeafNode.leftSplitCount
            let indexWithinNode = destIsNew ? i - LeafNode.leftSplitCount : i
            let destOffset = LeafNode.cellOffset(cellNum: indexWithinNode)

            if i == Int(cursor.cellNum) {
                let serialized = row.serialize()
                withUnsafeBytes(of: key) { src in
                    if destIsNew {
                        newPage.replaceSubrange(destOffset ..< destOffset + LeafNode.keySize, with: src)
                    } else {
                        oldPage.replaceSubrange(destOffset ..< destOffset + LeafNode.keySize, with: src)
                    }
                }
                let valueOff = destOffset + LeafNode.keySize
                if destIsNew {
                    newPage.replaceSubrange(valueOff ..< valueOff + Row.size, with: serialized)
                } else {
                    oldPage.replaceSubrange(valueOff ..< valueOff + Row.size, with: serialized)
                }
            } else {
                let srcIndex = i > Int(cursor.cellNum) ? i - 1 : i
                let srcOffset = LeafNode.cellOffset(cellNum: srcIndex)
                let srcRange = srcOffset ..< srcOffset + LeafNode.cellSize
                if destIsNew {
                    newPage.replaceSubrange(destOffset ..< destOffset + LeafNode.cellSize,
                                            with: oldPageCopy[srcRange])
                } else {
                    oldPage.replaceSubrange(destOffset ..< destOffset + LeafNode.cellSize,
                                            with: oldPageCopy[srcRange])
                }
            }
        }

        LeafNode.setNumCells(&oldPage, UInt32(LeafNode.leftSplitCount))
        LeafNode.setNumCells(&newPage, UInt32(LeafNode.rightSplitCount))
        pager.setPage(Int(cursor.pageNum), data: oldPage)
        _ = pager.getPage(newPageNum)
        pager.setPage(newPageNum, data: newPage)

        // TODO: Handle non-root splits by updating the parent node (Part 11).
        assert(BTreeNode.isRoot(oldPageCopy), "Need to implement updating parent after split")
        createNewRoot(rightChildPageNum: UInt32(newPageNum))
    }

    private func createNewRoot(rightChildPageNum: UInt32) {
        let oldRoot = pager.getPage(Int(rootPageNum))
        let leftChildPageNum = UInt32(pager.numPages)
        _ = pager.getPage(Int(leftChildPageNum))
        var leftChildPage = oldRoot
        BTreeNode.setIsRoot(&leftChildPage, false)

        var newRootPage = InternalNode.initialize()
        BTreeNode.setIsRoot(&newRootPage, true)
        InternalNode.setNumKeys(&newRootPage, 1)
        InternalNode.setChild(&newRootPage, childNum: 0, leftChildPageNum)
        let maxLeftKey = getNodeMaxKey(leftChildPage)
        InternalNode.setKey(&newRootPage, keyNum: 0, maxLeftKey)
        InternalNode.setRightChild(&newRootPage, rightChildPageNum)

        pager.setPage(Int(rootPageNum), data: newRootPage)
        pager.setPage(Int(leftChildPageNum), data: leftChildPage)
    }

    public func select() -> [Row] {
        let cursor = tableStart()
        var rows: [Row] = []
        while !cursor.endOfTable {
            let (pageIndex, byteOffset) = cursor.value()
            let page = pager.getPage(pageIndex)
            let slice = Data(page[byteOffset ..< byteOffset + Row.size])
            rows.append(Row.deserialize(from: slice))
            cursor.advance()
        }
        return rows
    }

    func printTree(pageNum: UInt32 = 0, indentation: Int = 0) {
        let page = pager.getPage(Int(pageNum))
        let indent = String(repeating: "  ", count: indentation)
        switch BTreeNode.nodeType(page) {
        case .leaf:
            let numCells = LeafNode.numCells(page)
            print("\(indent)- leaf (size \(numCells))")
            for i in 0 ..< numCells {
                print("\(indent)  - \(LeafNode.key(page, cellNum: Int(i)))")
            }
        case .internal:
            let numKeys = InternalNode.numKeys(page)
            print("\(indent)- internal (size \(numKeys))")
            for i in 0 ..< numKeys {
                let childPageNum = InternalNode.child(page, childNum: Int(i))
                printTree(pageNum: childPageNum, indentation: indentation + 1)
                print("\(indent)  - key \(InternalNode.key(page, keyNum: Int(i)))")
            }
            printTree(pageNum: InternalNode.rightChild(page), indentation: indentation + 1)
        }
    }
}
