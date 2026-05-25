import Foundation

class BTree {
    private let rootPageNum: UInt32 = 0
    private let pager: Pager
    private let internalNodeMaxCells: Int
    private var isClosed = false

    private struct Cursor {
        var pageNum: UInt32
        var cellNum: UInt32
        var endOfTable: Bool
    }

    init(pager: Pager, internalNodeMaxCells: Int = InternalNode.maxCells) {
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

    private func start() -> Cursor {
        find(key: 0)
    }

    var rows: some Sequence<Row> {
        sequence(state: start()) { [self] cursor in
            guard !cursor.endOfTable else { return nil }
            let row = row(at: cursor)
            cursor = advance(cursor)
            return row
        }
    }

    private func find(key: UInt32) -> Cursor {
        let page = pager.getPage(Int(rootPageNum))
        switch nodeType(page) {
        case .leaf:
            return leafNodeFind(pageNum: rootPageNum, key: key)
        case .internal:
            return internalNodeFind(pageNum: rootPageNum, key: key)
        }
    }

    // MARK: - Lifecycle

    func close() {
        guard !isClosed else { return }
        isClosed = true
        pager.flushAll()
        pager.close()
    }

    deinit {
        close()
    }

    // MARK: - Mutation

    func insert(row: Row) throws(ExecuteError) {
        let cursor = find(key: row.id)
        let node = LeafNode(pager.getPage(Int(cursor.pageNum)))
        if cursor.cellNum < UInt32(node.cells.count),
           node.key(cellNum: Int(cursor.cellNum)) == row.id
        {
            throw .duplicateKey
        }
        do {
            try leafNodeInsert(cursor: cursor, key: row.id, row: row)
        } catch {
            throw .tableFull
        }
    }

    private func leafNodeInsert(cursor: Cursor, key: UInt32, row: Row) throws(PagerError) {
        var node = LeafNode(pager.getPage(Int(cursor.pageNum)))
        if node.cells.count >= LeafNode.maxCells {
            try leafNodeSplitAndInsert(cursor: cursor, key: key, row: row)
            return
        }
        node.cells.insert((key: key, value: row.serialize()), at: Int(cursor.cellNum))
        pager.setPage(Int(cursor.pageNum), data: node.data)
    }

    // MARK: - Debug

    func printTree(pageNum: UInt32 = 0, indentation: Int = 0) {
        let page = pager.getPage(Int(pageNum))
        let indent = String(repeating: "  ", count: indentation)
        switch nodeType(page) {
        case .leaf:
            let node = LeafNode(page)
            print("\(indent)- leaf (size \(node.cells.count))")
            for i in 0 ..< node.cells.count {
                print("\(indent)  - \(node.key(cellNum: i))")
            }
        case .internal:
            let node = InternalNode(page)
            print("\(indent)- internal (size \(node.cells.count))")
            for i in 0 ..< node.cells.count {
                let childPageNum = node.child(childNum: i)
                printTree(pageNum: childPageNum, indentation: indentation + 1)
                print("\(indent)  - key \(node.key(keyNum: i))")
            }
            printTree(pageNum: node.rightChild, indentation: indentation + 1)
        }
    }

    // MARK: - Private row access

    private func row(at cursor: Cursor) -> Row {
        let page = pager.getPage(Int(cursor.pageNum))
        let offset = LeafNode.valueOffset(cellNum: Int(cursor.cellNum))
        return Row.deserialize(from: Data(page[offset ..< offset + Row.size]))
    }

    private func advance(_ cursor: Cursor) -> Cursor {
        var next = cursor
        let node = LeafNode(pager.getPage(Int(cursor.pageNum)))
        next.cellNum += 1
        if next.cellNum >= UInt32(node.cells.count) {
            let nextPageNum = node.nextLeaf
            if nextPageNum == 0 {
                next.endOfTable = true
            } else {
                next.pageNum = nextPageNum
                next.cellNum = 0
            }
        }
        return next
    }

    // MARK: - Private tree operations

    private func leafNodeFind(pageNum: UInt32, key: UInt32) -> Cursor {
        let node = LeafNode(pager.getPage(Int(pageNum)))
        let count = node.cells.count
        var minIndex = 0
        var onePastMaxIndex = count
        while minIndex < onePastMaxIndex {
            let index = (minIndex + onePastMaxIndex) / 2
            let keyAtIndex = node.key(cellNum: index)
            if key == keyAtIndex {
                return Cursor(pageNum: pageNum, cellNum: UInt32(index), endOfTable: false)
            }
            if key < keyAtIndex {
                onePastMaxIndex = index
            } else {
                minIndex = index + 1
            }
        }
        return Cursor(pageNum: pageNum, cellNum: UInt32(minIndex), endOfTable: minIndex >= count)
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

    private func leafNodeSplitAndInsert(cursor: Cursor, key: UInt32, row: Row) throws(PagerError) {
        var oldNode = LeafNode(pager.getPage(Int(cursor.pageNum)))
        let oldMaxKey = getNodeMaxKey(oldNode.data)
        let oldNextLeaf = oldNode.nextLeaf
        let newPageNum = try pager.allocatePage()
        var newNode = LeafNode.makeNew()

        var allCells = oldNode.cells
        allCells.insert((key: key, value: row.serialize()), at: Int(cursor.cellNum))

        oldNode.cells = Array(allCells[0 ..< LeafNode.leftSplitCount])
        newNode.cells = Array(allCells[LeafNode.leftSplitCount...])

        oldNode.nextLeaf = UInt32(newPageNum)
        newNode.nextLeaf = oldNextLeaf
        pager.setPage(Int(cursor.pageNum), data: oldNode.data)
        pager.setPage(newPageNum, data: newNode.data)

        if oldNode.isRoot {
            try createNewRoot(rightChildPageNum: UInt32(newPageNum))
        } else {
            let parentPageNum = oldNode.parent
            let newMaxKey = getNodeMaxKey(oldNode.data)
            updateInternalNodeKey(pageNum: parentPageNum, oldKey: oldMaxKey, newKey: newMaxKey)
            try internalNodeInsert(parentPageNum: parentPageNum, childPageNum: UInt32(newPageNum))
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

    private func createNewRoot(rightChildPageNum: UInt32) throws(PagerError) {
        let leftChildPageNum = try UInt32(pager.allocatePage())
        var leftChildPage = pager.getPage(Int(rootPageNum))
        setIsRoot(&leftChildPage, false)
        setParent(&leftChildPage, rootPageNum)

        let maxLeftKey = getNodeMaxKey(leftChildPage)
        var newRoot = InternalNode.makeNew()
        newRoot.isRoot = true
        newRoot.cells.append((child: leftChildPageNum, key: maxLeftKey))
        newRoot.rightChild = rightChildPageNum

        pager.setPage(Int(rootPageNum), data: newRoot.data)
        pager.setPage(Int(leftChildPageNum), data: leftChildPage)

        if nodeType(leftChildPage) == .internal {
            let leftInternal = InternalNode(leftChildPage)
            for i in 0 ... leftInternal.cells.count {
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
        // The rightmost child's max key is not stored in the parent's cells; nothing to update.
        guard index < node.cells.count else { return }
        node.setKey(keyNum: index, newKey)
        pager.setPage(Int(pageNum), data: node.data)
    }

    private func internalNodeInsert(parentPageNum: UInt32, childPageNum: UInt32) throws(PagerError) {
        var parent = InternalNode(pager.getPage(Int(parentPageNum)))
        let childMaxKey = getNodeMaxKey(pager.getPage(Int(childPageNum)))
        let index = parent.findChildIndex(key: childMaxKey)

        if parent.cells.count >= internalNodeMaxCells {
            try internalNodeSplitAndInsert(parentPageNum: parentPageNum, childPageNum: childPageNum)
            return
        }

        let rightChildPageNum = parent.rightChild
        if rightChildPageNum == InternalNode.invalidPageNum {
            parent.rightChild = childPageNum
            pager.setPage(Int(parentPageNum), data: parent.data)
            return
        }

        let rightChildMaxKey = getNodeMaxKey(pager.getPage(Int(rightChildPageNum)))
        if childMaxKey > rightChildMaxKey {
            parent.cells.append((child: rightChildPageNum, key: rightChildMaxKey))
            parent.rightChild = childPageNum
        } else {
            parent.cells.insert((child: childPageNum, key: childMaxKey), at: index)
        }
        pager.setPage(Int(parentPageNum), data: parent.data)
    }

    private func internalNodeSplitAndInsert(parentPageNum: UInt32, childPageNum: UInt32) throws(PagerError) {
        let oldPage = pager.getPage(Int(parentPageNum))
        let oldMax = getNodeMaxKey(oldPage)
        let childMax = getNodeMaxKey(pager.getPage(Int(childPageNum)))
        let newPageNum = try pager.allocatePage()

        let oldNode = InternalNode(oldPage)
        let splittingRoot = oldNode.isRoot
        let grandparentPageNum: UInt32
        let actualOldPageNum: UInt32

        if splittingRoot {
            let newNode = InternalNode.makeNew()
            pager.setPage(newPageNum, data: newNode.data)
            try createNewRoot(rightChildPageNum: UInt32(newPageNum))
            let rootNode = InternalNode(pager.getPage(Int(rootPageNum)))
            actualOldPageNum = rootNode.child(childNum: 0)
            grandparentPageNum = rootPageNum
        } else {
            actualOldPageNum = parentPageNum
            grandparentPageNum = oldNode.parent
            let newNode = InternalNode.makeNew()
            pager.setPage(newPageNum, data: newNode.data)
        }

        // Move old node's rightChild into new node
        var actualOldNode = InternalNode(pager.getPage(Int(actualOldPageNum)))
        let rightChildPageNum = actualOldNode.rightChild
        try internalNodeInsert(parentPageNum: UInt32(newPageNum), childPageNum: rightChildPageNum)
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
            let childToMovePageNum = actualOldNode.cells[i].child
            try internalNodeInsert(parentPageNum: UInt32(newPageNum), childPageNum: childToMovePageNum)
            var childToMovePage = pager.getPage(Int(childToMovePageNum))
            setParent(&childToMovePage, UInt32(newPageNum))
            pager.setPage(Int(childToMovePageNum), data: childToMovePage)

            actualOldNode = InternalNode(pager.getPage(Int(actualOldPageNum)))
            actualOldNode.cells.removeLast()
            pager.setPage(Int(actualOldPageNum), data: actualOldNode.data)
        }

        // Promote: last remaining cell of old becomes its new rightChild
        actualOldNode = InternalNode(pager.getPage(Int(actualOldPageNum)))
        let newRightChild = actualOldNode.cells.last!.child
        actualOldNode.rightChild = newRightChild
        actualOldNode.cells.removeLast()
        pager.setPage(Int(actualOldPageNum), data: actualOldNode.data)

        // Insert new child into whichever node its key belongs to
        let maxAfterSplit = getNodeMaxKey(pager.getPage(Int(actualOldPageNum)))
        let destPageNum = childMax < maxAfterSplit ? actualOldPageNum : UInt32(newPageNum)
        try internalNodeInsert(parentPageNum: destPageNum, childPageNum: childPageNum)
        var childPageData = pager.getPage(Int(childPageNum))
        setParent(&childPageData, destPageNum)
        pager.setPage(Int(childPageNum), data: childPageData)

        // Update grandparent's key for old node
        updateInternalNodeKey(pageNum: grandparentPageNum, oldKey: oldMax,
                              newKey: getNodeMaxKey(pager.getPage(Int(actualOldPageNum))))

        // If not root split, insert new node into grandparent
        if !splittingRoot {
            try internalNodeInsert(parentPageNum: grandparentPageNum, childPageNum: UInt32(newPageNum))
            var newPageData = pager.getPage(newPageNum)
            setParent(&newPageData, grandparentPageNum)
            pager.setPage(newPageNum, data: newPageData)
        }
    }
}
