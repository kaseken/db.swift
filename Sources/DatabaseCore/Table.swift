import Foundation

public enum ExecuteResult {
    case success
    case duplicateKey
}

public class Table {
    let rootPageNum: UInt32 = 0
    let pager: Pager
    let internalNodeMaxCells: Int

    public init(filename: String, internalNodeMaxCells: Int? = nil) throws {
        self.internalNodeMaxCells = internalNodeMaxCells
            ?? (Pager.pageSize - InternalNode.headerSize) / InternalNode.cellSize
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
        tableFind(key: 0)
    }

    private func internalNodeFind(pageNum: UInt32, key: UInt32) -> Cursor {
        let page = pager.getPage(Int(pageNum))
        let childIndex = InternalNode.findChildIndex(page, key: key)
        let childPageNum = InternalNode.child(page, childNum: childIndex)
        let childPage = pager.getPage(Int(childPageNum))
        switch BTreeNode.nodeType(childPage) {
        case .leaf:
            return leafNodeFind(pageNum: childPageNum, key: key)
        case .internal:
            return internalNodeFind(pageNum: childPageNum, key: key)
        }
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
            return internalNodeFind(pageNum: rootPageNum, key: key)
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
        let oldMaxKey = getNodeMaxKey(oldPageCopy)
        var oldPage = oldPageCopy
        let oldNextLeaf = LeafNode.nextLeaf(oldPageCopy)
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
        LeafNode.setNextLeaf(&oldPage, UInt32(newPageNum))
        LeafNode.setNumCells(&newPage, UInt32(LeafNode.rightSplitCount))
        LeafNode.setNextLeaf(&newPage, oldNextLeaf)
        pager.setPage(Int(cursor.pageNum), data: oldPage)
        _ = pager.getPage(newPageNum)
        pager.setPage(newPageNum, data: newPage)

        if BTreeNode.isRoot(oldPageCopy) {
            createNewRoot(rightChildPageNum: UInt32(newPageNum))
        } else {
            let parentPageNum = BTreeNode.parent(oldPageCopy)
            let newMaxKey = getNodeMaxKey(oldPage)
            updateInternalNodeKey(pageNum: parentPageNum, oldKey: oldMaxKey, newKey: newMaxKey)
            internalNodeInsert(parentPageNum: parentPageNum, childPageNum: UInt32(newPageNum))
        }
    }

    private func getNodeMaxKey(_ page: Data) -> UInt32 {
        switch BTreeNode.nodeType(page) {
        case .leaf:
            return LeafNode.key(page, cellNum: Int(LeafNode.numCells(page)) - 1)
        case .internal:
            let rightChildPage = pager.getPage(Int(InternalNode.rightChild(page)))
            return getNodeMaxKey(rightChildPage)
        }
    }

    private func createNewRoot(rightChildPageNum: UInt32) {
        let oldRoot = pager.getPage(Int(rootPageNum))
        let leftChildPageNum = UInt32(pager.numPages)
        _ = pager.getPage(Int(leftChildPageNum))
        var leftChildPage = oldRoot
        BTreeNode.setIsRoot(&leftChildPage, false)
        BTreeNode.setParent(&leftChildPage, rootPageNum)

        var newRootPage = InternalNode.initialize()
        BTreeNode.setIsRoot(&newRootPage, true)
        InternalNode.setNumKeys(&newRootPage, 1)
        InternalNode.setChild(&newRootPage, childNum: 0, leftChildPageNum)
        let maxLeftKey = getNodeMaxKey(leftChildPage)
        InternalNode.setKey(&newRootPage, keyNum: 0, maxLeftKey)
        InternalNode.setRightChild(&newRootPage, rightChildPageNum)

        pager.setPage(Int(rootPageNum), data: newRootPage)
        pager.setPage(Int(leftChildPageNum), data: leftChildPage)

        if BTreeNode.nodeType(leftChildPage) == .internal {
            let numKeys = InternalNode.numKeys(leftChildPage)
            for i in 0 ... Int(numKeys) {
                let childPageNum = InternalNode.child(leftChildPage, childNum: i)
                var childPage = pager.getPage(Int(childPageNum))
                BTreeNode.setParent(&childPage, leftChildPageNum)
                pager.setPage(Int(childPageNum), data: childPage)
            }
        }

        var rightChildPage = pager.getPage(Int(rightChildPageNum))
        BTreeNode.setParent(&rightChildPage, rootPageNum)
        pager.setPage(Int(rightChildPageNum), data: rightChildPage)
    }

    private func updateInternalNodeKey(pageNum: UInt32, oldKey: UInt32, newKey: UInt32) {
        var page = pager.getPage(Int(pageNum))
        let index = InternalNode.findChildIndex(page, key: oldKey)
        InternalNode.setKey(&page, keyNum: index, newKey)
        pager.setPage(Int(pageNum), data: page)
    }

    private func internalNodeInsert(parentPageNum: UInt32, childPageNum: UInt32) {
        var parentPage = pager.getPage(Int(parentPageNum))
        let childPage = pager.getPage(Int(childPageNum))
        let childMaxKey = getNodeMaxKey(childPage)
        let index = InternalNode.findChildIndex(parentPage, key: childMaxKey)
        let originalNumKeys = InternalNode.numKeys(parentPage)

        if originalNumKeys >= UInt32(internalNodeMaxCells) {
            internalNodeSplitAndInsert(parentPageNum: parentPageNum, childPageNum: childPageNum)
            return
        }

        InternalNode.setNumKeys(&parentPage, originalNumKeys + 1)

        let rightChildPageNum = InternalNode.rightChild(parentPage)
        if rightChildPageNum == BTreeNode.invalidPageNum {
            InternalNode.setRightChild(&parentPage, childPageNum)
            pager.setPage(Int(parentPageNum), data: parentPage)
            return
        }

        let rightChildPage = pager.getPage(Int(rightChildPageNum))
        if childMaxKey > getNodeMaxKey(rightChildPage) {
            InternalNode.setChild(&parentPage, childNum: Int(originalNumKeys), rightChildPageNum)
            InternalNode.setKey(&parentPage, keyNum: Int(originalNumKeys), getNodeMaxKey(rightChildPage))
            InternalNode.setRightChild(&parentPage, childPageNum)
        } else {
            for i in stride(from: Int(originalNumKeys), through: Int(index) + 1, by: -1) {
                let src = InternalNode.cellOffset(cellNum: i - 1)
                let dst = InternalNode.cellOffset(cellNum: i)
                parentPage.replaceSubrange(dst ..< dst + InternalNode.cellSize,
                                           with: parentPage[src ..< src + InternalNode.cellSize])
            }
            InternalNode.setChild(&parentPage, childNum: Int(index), childPageNum)
            InternalNode.setKey(&parentPage, keyNum: Int(index), childMaxKey)
        }
        pager.setPage(Int(parentPageNum), data: parentPage)
    }

    private func internalNodeSplitAndInsert(parentPageNum: UInt32, childPageNum: UInt32) {
        let oldPage = pager.getPage(Int(parentPageNum))
        let oldMax = getNodeMaxKey(oldPage)
        let childPage = pager.getPage(Int(childPageNum))
        let childMax = getNodeMaxKey(childPage)
        let newPageNum = pager.numPages

        let splittingRoot = BTreeNode.isRoot(oldPage)
        let grandparentPageNum: UInt32
        let actualOldPageNum: UInt32

        if splittingRoot {
            createNewRoot(rightChildPageNum: UInt32(newPageNum))
            let rootPage = pager.getPage(Int(rootPageNum))
            actualOldPageNum = InternalNode.child(rootPage, childNum: 0)
            grandparentPageNum = rootPageNum
        } else {
            actualOldPageNum = parentPageNum
            grandparentPageNum = BTreeNode.parent(oldPage)
            var newPage = InternalNode.initialize()
            _ = pager.getPage(newPageNum)
            pager.setPage(newPageNum, data: newPage)
        }

        // Move old node's rightChild into new node
        var actualOldPage = pager.getPage(Int(actualOldPageNum))
        let rightChildPageNum = InternalNode.rightChild(actualOldPage)
        internalNodeInsert(parentPageNum: UInt32(newPageNum), childPageNum: rightChildPageNum)
        var rightChildPage = pager.getPage(Int(rightChildPageNum))
        BTreeNode.setParent(&rightChildPage, UInt32(newPageNum))
        pager.setPage(Int(rightChildPageNum), data: rightChildPage)

        // Invalidate old node's rightChild
        actualOldPage = pager.getPage(Int(actualOldPageNum))
        InternalNode.setRightChild(&actualOldPage, BTreeNode.invalidPageNum)
        pager.setPage(Int(actualOldPageNum), data: actualOldPage)

        // Move upper half of old node's cells to new node
        for i in stride(from: internalNodeMaxCells - 1, through: internalNodeMaxCells / 2 + 1, by: -1) {
            actualOldPage = pager.getPage(Int(actualOldPageNum))
            let childToMovePageNum = InternalNode.child(actualOldPage, childNum: i)
            internalNodeInsert(parentPageNum: UInt32(newPageNum), childPageNum: childToMovePageNum)
            var childToMovePage = pager.getPage(Int(childToMovePageNum))
            BTreeNode.setParent(&childToMovePage, UInt32(newPageNum))
            pager.setPage(Int(childToMovePageNum), data: childToMovePage)

            actualOldPage = pager.getPage(Int(actualOldPageNum))
            let curNumKeys = InternalNode.numKeys(actualOldPage)
            InternalNode.setNumKeys(&actualOldPage, curNumKeys - 1)
            pager.setPage(Int(actualOldPageNum), data: actualOldPage)
        }

        // Promote: last remaining cell of old becomes its new rightChild
        actualOldPage = pager.getPage(Int(actualOldPageNum))
        let curNumKeys = InternalNode.numKeys(actualOldPage)
        let newRightChild = InternalNode.child(actualOldPage, childNum: Int(curNumKeys) - 1)
        InternalNode.setRightChild(&actualOldPage, newRightChild)
        InternalNode.setNumKeys(&actualOldPage, curNumKeys - 1)
        pager.setPage(Int(actualOldPageNum), data: actualOldPage)

        // Insert new child into whichever node its key belongs to
        actualOldPage = pager.getPage(Int(actualOldPageNum))
        let maxAfterSplit = getNodeMaxKey(actualOldPage)
        let destPageNum = childMax < maxAfterSplit ? actualOldPageNum : UInt32(newPageNum)
        internalNodeInsert(parentPageNum: destPageNum, childPageNum: childPageNum)
        var childPageMut = pager.getPage(Int(childPageNum))
        BTreeNode.setParent(&childPageMut, destPageNum)
        pager.setPage(Int(childPageNum), data: childPageMut)

        // Update grandparent's key for old node
        actualOldPage = pager.getPage(Int(actualOldPageNum))
        updateInternalNodeKey(pageNum: grandparentPageNum, oldKey: oldMax, newKey: getNodeMaxKey(actualOldPage))

        // If not root split, insert new node into grandparent
        if !splittingRoot {
            internalNodeInsert(parentPageNum: grandparentPageNum, childPageNum: UInt32(newPageNum))
            var newPage = pager.getPage(newPageNum)
            BTreeNode.setParent(&newPage, grandparentPageNum)
            pager.setPage(newPageNum, data: newPage)
        }
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
