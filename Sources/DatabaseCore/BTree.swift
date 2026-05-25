import Foundation

class BTree {
    let rootPageNum: UInt32 = 0
    let pager: Pager
    let internalNodeMaxCells: Int

    init(pager: Pager, internalNodeMaxCells: Int) {
        self.pager = pager
        self.internalNodeMaxCells = internalNodeMaxCells
        if pager.numPages == 0 {
            _ = pager.getPage(0)
            var root = LeafNode.makeNew()
            root.isRoot = true
            pager.setPage(0, data: root.data)
        }
    }

    // MARK: - Navigation

    func start() -> Cursor {
        find(key: 0)
    }

    func find(key: UInt32) -> Cursor {
        let page = pager.getPage(Int(rootPageNum))
        switch nodeType(page) {
        case .leaf:
            return leafNodeFind(pageNum: rootPageNum, key: key)
        case .internal:
            return internalNodeFind(pageNum: rootPageNum, key: key)
        }
    }

    // MARK: - Mutation

    func leafNodeInsert(cursor: Cursor, key: UInt32, row: Row) {
        var node = LeafNode(pager.getPage(Int(cursor.pageNum)))
        let numCells = node.numCells
        if numCells >= UInt32(LeafNode.maxCells) {
            leafNodeSplitAndInsert(cursor: cursor, key: key, row: row)
            return
        }
        if cursor.cellNum < numCells {
            var i = numCells
            while i > cursor.cellNum {
                let src = LeafNode.cellOffset(cellNum: Int(i) - 1)
                let dst = LeafNode.cellOffset(cellNum: Int(i))
                node.data.replaceSubrange(dst ..< dst + LeafNode.cellSize, with: node.data[src ..< src + LeafNode.cellSize])
                i -= 1
            }
        }
        node.numCells = numCells + 1
        node.setKey(cellNum: Int(cursor.cellNum), key: key)
        let serialized = row.serialize()
        let valueOff = LeafNode.valueOffset(cellNum: Int(cursor.cellNum))
        node.data.replaceSubrange(valueOff ..< valueOff + Row.size, with: serialized)
        pager.setPage(Int(cursor.pageNum), data: node.data)
    }

    // MARK: - Debug

    func printTree(pageNum: UInt32 = 0, indentation: Int = 0) {
        let page = pager.getPage(Int(pageNum))
        let indent = String(repeating: "  ", count: indentation)
        switch nodeType(page) {
        case .leaf:
            let node = LeafNode(page)
            print("\(indent)- leaf (size \(node.numCells))")
            for i in 0 ..< node.numCells {
                print("\(indent)  - \(node.key(cellNum: Int(i)))")
            }
        case .internal:
            let node = InternalNode(page)
            print("\(indent)- internal (size \(node.numKeys))")
            for i in 0 ..< node.numKeys {
                let childPageNum = node.child(childNum: Int(i))
                printTree(pageNum: childPageNum, indentation: indentation + 1)
                print("\(indent)  - key \(node.key(keyNum: Int(i)))")
            }
            printTree(pageNum: node.rightChild, indentation: indentation + 1)
        }
    }

    // MARK: - Private tree operations

    private func leafNodeFind(pageNum: UInt32, key: UInt32) -> Cursor {
        let node = LeafNode(pager.getPage(Int(pageNum)))
        let numCells = node.numCells
        var minIndex: UInt32 = 0
        var onePastMaxIndex = numCells
        while minIndex < onePastMaxIndex {
            let index = (minIndex + onePastMaxIndex) / 2
            let keyAtIndex = node.key(cellNum: Int(index))
            if key == keyAtIndex {
                return Cursor(btree: self, pageNum: pageNum, cellNum: index, endOfTable: false)
            }
            if key < keyAtIndex {
                onePastMaxIndex = index
            } else {
                minIndex = index + 1
            }
        }
        return Cursor(btree: self, pageNum: pageNum, cellNum: minIndex, endOfTable: minIndex >= numCells)
    }

    private func internalNodeFind(pageNum: UInt32, key: UInt32) -> Cursor {
        let node = InternalNode(pager.getPage(Int(pageNum)))
        let childIndex = node.findChildIndex(key: key)
        let childPageNum = node.child(childNum: childIndex)
        let childPage = pager.getPage(Int(childPageNum))
        switch nodeType(childPage) {
        case .leaf:
            return leafNodeFind(pageNum: childPageNum, key: key)
        case .internal:
            return internalNodeFind(pageNum: childPageNum, key: key)
        }
    }

    private func leafNodeSplitAndInsert(cursor: Cursor, key: UInt32, row: Row) {
        let oldNodeCopy = LeafNode(pager.getPage(Int(cursor.pageNum)))
        let oldMaxKey = getNodeMaxKey(oldNodeCopy.data)
        var oldNode = oldNodeCopy
        let oldNextLeaf = oldNodeCopy.nextLeaf
        let newPageNum = pager.numPages
        var newNode = LeafNode.makeNew()

        for i in stride(from: LeafNode.maxCells, through: 0, by: -1) {
            let destIsNew = i >= LeafNode.leftSplitCount
            let indexWithinNode = destIsNew ? i - LeafNode.leftSplitCount : i
            let destOffset = LeafNode.cellOffset(cellNum: indexWithinNode)

            if i == Int(cursor.cellNum) {
                let serialized = row.serialize()
                withUnsafeBytes(of: key) { src in
                    if destIsNew {
                        newNode.data.replaceSubrange(destOffset ..< destOffset + LeafNode.keySize, with: src)
                    } else {
                        oldNode.data.replaceSubrange(destOffset ..< destOffset + LeafNode.keySize, with: src)
                    }
                }
                let valueOff = destOffset + LeafNode.keySize
                if destIsNew {
                    newNode.data.replaceSubrange(valueOff ..< valueOff + Row.size, with: serialized)
                } else {
                    oldNode.data.replaceSubrange(valueOff ..< valueOff + Row.size, with: serialized)
                }
            } else {
                let srcIndex = i > Int(cursor.cellNum) ? i - 1 : i
                let srcOffset = LeafNode.cellOffset(cellNum: srcIndex)
                let srcRange = srcOffset ..< srcOffset + LeafNode.cellSize
                if destIsNew {
                    newNode.data.replaceSubrange(destOffset ..< destOffset + LeafNode.cellSize,
                                                 with: oldNodeCopy.data[srcRange])
                } else {
                    oldNode.data.replaceSubrange(destOffset ..< destOffset + LeafNode.cellSize,
                                                 with: oldNodeCopy.data[srcRange])
                }
            }
        }

        oldNode.numCells = UInt32(LeafNode.leftSplitCount)
        oldNode.nextLeaf = UInt32(newPageNum)
        newNode.numCells = UInt32(LeafNode.rightSplitCount)
        newNode.nextLeaf = oldNextLeaf
        pager.setPage(Int(cursor.pageNum), data: oldNode.data)
        _ = pager.getPage(newPageNum)
        pager.setPage(newPageNum, data: newNode.data)

        if oldNodeCopy.isRoot {
            createNewRoot(rightChildPageNum: UInt32(newPageNum))
        } else {
            let parentPageNum = oldNodeCopy.parent
            let newMaxKey = getNodeMaxKey(oldNode.data)
            updateInternalNodeKey(pageNum: parentPageNum, oldKey: oldMaxKey, newKey: newMaxKey)
            internalNodeInsert(parentPageNum: parentPageNum, childPageNum: UInt32(newPageNum))
        }
    }

    private func getNodeMaxKey(_ data: Data) -> UInt32 {
        switch nodeType(data) {
        case .leaf:
            return LeafNode(data).maxKey
        case .internal:
            let node = InternalNode(data)
            return getNodeMaxKey(pager.getPage(Int(node.rightChild)))
        }
    }

    private func createNewRoot(rightChildPageNum: UInt32) {
        let leftChildPageNum = UInt32(pager.numPages)
        _ = pager.getPage(Int(leftChildPageNum))
        var leftChildPage = pager.getPage(Int(rootPageNum))
        setIsRoot(&leftChildPage, false)
        setParent(&leftChildPage, rootPageNum)

        var newRoot = InternalNode.makeNew()
        newRoot.isRoot = true
        newRoot.numKeys = 1
        newRoot.setChild(childNum: 0, leftChildPageNum)
        let maxLeftKey = getNodeMaxKey(leftChildPage)
        newRoot.setKey(keyNum: 0, maxLeftKey)
        newRoot.rightChild = rightChildPageNum

        pager.setPage(Int(rootPageNum), data: newRoot.data)
        pager.setPage(Int(leftChildPageNum), data: leftChildPage)

        if nodeType(leftChildPage) == .internal {
            let leftInternal = InternalNode(leftChildPage)
            let numKeys = leftInternal.numKeys
            for i in 0 ... Int(numKeys) {
                let childPageNum = leftInternal.child(childNum: i)
                var childPage = pager.getPage(Int(childPageNum))
                setParent(&childPage, leftChildPageNum)
                pager.setPage(Int(childPageNum), data: childPage)
            }
        }

        var rightChildPage = pager.getPage(Int(rightChildPageNum))
        setParent(&rightChildPage, rootPageNum)
        pager.setPage(Int(rightChildPageNum), data: rightChildPage)
    }

    private func updateInternalNodeKey(pageNum: UInt32, oldKey: UInt32, newKey: UInt32) {
        var node = InternalNode(pager.getPage(Int(pageNum)))
        let index = node.findChildIndex(key: oldKey)
        node.setKey(keyNum: index, newKey)
        pager.setPage(Int(pageNum), data: node.data)
    }

    private func internalNodeInsert(parentPageNum: UInt32, childPageNum: UInt32) {
        var parent = InternalNode(pager.getPage(Int(parentPageNum)))
        let childMaxKey = getNodeMaxKey(pager.getPage(Int(childPageNum)))
        let index = parent.findChildIndex(key: childMaxKey)
        let originalNumKeys = parent.numKeys

        if originalNumKeys >= UInt32(internalNodeMaxCells) {
            internalNodeSplitAndInsert(parentPageNum: parentPageNum, childPageNum: childPageNum)
            return
        }

        parent.numKeys = originalNumKeys + 1

        let rightChildPageNum = parent.rightChild
        if rightChildPageNum == InternalNode.invalidPageNum {
            parent.rightChild = childPageNum
            pager.setPage(Int(parentPageNum), data: parent.data)
            return
        }

        let rightChildMaxKey = getNodeMaxKey(pager.getPage(Int(rightChildPageNum)))
        if childMaxKey > rightChildMaxKey {
            parent.setChild(childNum: Int(originalNumKeys), rightChildPageNum)
            parent.setKey(keyNum: Int(originalNumKeys), rightChildMaxKey)
            parent.rightChild = childPageNum
        } else {
            for i in stride(from: Int(originalNumKeys), through: Int(index) + 1, by: -1) {
                let src = InternalNode.cellOffset(cellNum: i - 1)
                let dst = InternalNode.cellOffset(cellNum: i)
                parent.data.replaceSubrange(dst ..< dst + InternalNode.cellSize,
                                            with: parent.data[src ..< src + InternalNode.cellSize])
            }
            parent.setChild(childNum: Int(index), childPageNum)
            parent.setKey(keyNum: Int(index), childMaxKey)
        }
        pager.setPage(Int(parentPageNum), data: parent.data)
    }

    private func internalNodeSplitAndInsert(parentPageNum: UInt32, childPageNum: UInt32) {
        let oldPage = pager.getPage(Int(parentPageNum))
        let oldMax = getNodeMaxKey(oldPage)
        let childMax = getNodeMaxKey(pager.getPage(Int(childPageNum)))
        let newPageNum = pager.numPages

        let oldNode = InternalNode(oldPage)
        let splittingRoot = oldNode.isRoot
        let grandparentPageNum: UInt32
        let actualOldPageNum: UInt32

        if splittingRoot {
            let newNode = InternalNode.makeNew()
            _ = pager.getPage(newPageNum)
            pager.setPage(newPageNum, data: newNode.data)
            createNewRoot(rightChildPageNum: UInt32(newPageNum))
            let rootNode = InternalNode(pager.getPage(Int(rootPageNum)))
            actualOldPageNum = rootNode.child(childNum: 0)
            grandparentPageNum = rootPageNum
        } else {
            actualOldPageNum = parentPageNum
            grandparentPageNum = oldNode.parent
            let newNode = InternalNode.makeNew()
            _ = pager.getPage(newPageNum)
            pager.setPage(newPageNum, data: newNode.data)
        }

        // Move old node's rightChild into new node
        var actualOldNode = InternalNode(pager.getPage(Int(actualOldPageNum)))
        let rightChildPageNum = actualOldNode.rightChild
        internalNodeInsert(parentPageNum: UInt32(newPageNum), childPageNum: rightChildPageNum)
        var rightChildPage = pager.getPage(Int(rightChildPageNum))
        setParent(&rightChildPage, UInt32(newPageNum))
        pager.setPage(Int(rightChildPageNum), data: rightChildPage)

        // Invalidate old node's rightChild
        actualOldNode = InternalNode(pager.getPage(Int(actualOldPageNum)))
        actualOldNode.rightChild = InternalNode.invalidPageNum
        pager.setPage(Int(actualOldPageNum), data: actualOldNode.data)

        // Move upper half of old node's cells to new node
        for i in stride(from: internalNodeMaxCells - 1, through: internalNodeMaxCells / 2 + 1, by: -1) {
            actualOldNode = InternalNode(pager.getPage(Int(actualOldPageNum)))
            let childToMovePageNum = actualOldNode.child(childNum: i)
            internalNodeInsert(parentPageNum: UInt32(newPageNum), childPageNum: childToMovePageNum)
            var childToMovePage = pager.getPage(Int(childToMovePageNum))
            setParent(&childToMovePage, UInt32(newPageNum))
            pager.setPage(Int(childToMovePageNum), data: childToMovePage)

            actualOldNode = InternalNode(pager.getPage(Int(actualOldPageNum)))
            actualOldNode.numKeys -= 1
            pager.setPage(Int(actualOldPageNum), data: actualOldNode.data)
        }

        // Promote: last remaining cell of old becomes its new rightChild
        actualOldNode = InternalNode(pager.getPage(Int(actualOldPageNum)))
        let newRightChild = actualOldNode.child(childNum: Int(actualOldNode.numKeys) - 1)
        actualOldNode.rightChild = newRightChild
        actualOldNode.numKeys -= 1
        pager.setPage(Int(actualOldPageNum), data: actualOldNode.data)

        // Insert new child into whichever node its key belongs to
        let maxAfterSplit = getNodeMaxKey(pager.getPage(Int(actualOldPageNum)))
        let destPageNum = childMax < maxAfterSplit ? actualOldPageNum : UInt32(newPageNum)
        internalNodeInsert(parentPageNum: destPageNum, childPageNum: childPageNum)
        var childPageData = pager.getPage(Int(childPageNum))
        setParent(&childPageData, destPageNum)
        pager.setPage(Int(childPageNum), data: childPageData)

        // Update grandparent's key for old node
        updateInternalNodeKey(pageNum: grandparentPageNum, oldKey: oldMax,
                              newKey: getNodeMaxKey(pager.getPage(Int(actualOldPageNum))))

        // If not root split, insert new node into grandparent
        if !splittingRoot {
            internalNodeInsert(parentPageNum: grandparentPageNum, childPageNum: UInt32(newPageNum))
            var newPageData = pager.getPage(newPageNum)
            setParent(&newPageData, grandparentPageNum)
            pager.setPage(newPageNum, data: newPageData)
        }
    }
}
