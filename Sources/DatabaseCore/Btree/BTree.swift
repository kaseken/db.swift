import Foundation

class BTree {
    private let rootPageNum: UInt32 = 0
    private let pager: Pager
    private let internalNodeMaxCells: Int
    private var isClosed = false

    /// - Parameter internalNodeMaxCells: For testing only. Defaults to `InternalNode.maxCells`.
    init(pager: Pager, internalNodeMaxCells: Int = InternalNode.maxCells) throws(PagerError) {
        self.pager = pager
        self.internalNodeMaxCells = internalNodeMaxCells
        // If the database is new, initialize the tree with an empty root leaf node.
        if pager.numPages == 0 {
            let page = try pager.allocatePage()
            let root = LeafNode(pageNum: page.pageNum, isRoot: true, parentPageNum: 0, nextLeafPageNum: 0, cells: [])
            pager.setPage(Int(root.pageNum), data: root.data)
        }
    }

    // MARK: - Navigation

    private func start() -> Cursor {
        insertionPoint(for: 0)
    }

    var rows: some Sequence<Row> {
        sequence(state: start()) { [self] cursor in
            guard !cursor.endOfTable else { return nil }
            let row = row(at: cursor)
            cursor = advance(cursor)
            return row
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
        let cursor = insertionPoint(for: row.id)
        let node = cursor.node
        if cursor.cellNum < UInt32(node.cells.count),
           node.key(at: Int(cursor.cellNum)) == row.id
        {
            throw .duplicateKey
        }
        do {
            try leafNodeInsert(cursor: cursor, key: row.id, row: row)
        } catch {
            // leafNodeInsert throws(PagerError); the only reachable case here is .tableFull
            throw ExecuteError.tableFull
        }
    }

    private func leafNodeInsert(cursor: Cursor, key: UInt32, row: Row) throws(PagerError) {
        var node = cursor.node
        if node.cells.count >= LeafNode.maxCells {
            try leafNodeSplitAndInsert(cursor: cursor, key: key, row: row)
            return
        }
        node.cells.insert((key: key, value: row.serialize()), at: Int(cursor.cellNum))
        pager.setPage(Int(node.pageNum), data: node.data)
    }

    // MARK: - Debug

    func printTree() {
        BTreePrinter(pager: pager).printTree()
    }

    // MARK: - Private row access

    private func row(at cursor: Cursor) -> Row {
        Row.deserialize(from: cursor.node.cells[Int(cursor.cellNum)].value)
    }

    private func advance(_ cursor: Cursor) -> Cursor {
        var next = cursor
        next.cellNum += 1
        if next.cellNum >= UInt32(cursor.node.cells.count) {
            let nextPageNum = cursor.node.nextLeafPageNum
            if nextPageNum == 0 {
                next.endOfTable = true
            } else {
                next.node = LeafNode.restore(from: try! pager.getPage(Int(nextPageNum)))
                next.cellNum = 0
            }
        }
        return next
    }

    private func insertionPoint(for key: UInt32) -> Cursor {
        switch BTreeNodeFactory.restore(from: try! pager.getPage(Int(rootPageNum))) {
        case let .leaf(node): node.insertionPoint(for: key)
        case let .internal(node): node.insertionPoint(for: key, pager: pager)
        }
    }

    private func leafNodeSplitAndInsert(cursor: Cursor, key: UInt32, row: Row) throws(PagerError) {
        var oldNode = cursor.node
        let oldMaxKey = getNodeMaxKey(pageNum: oldNode.pageNum)
        let oldNextLeaf = oldNode.nextLeafPageNum
        var allCells = oldNode.cells
        allCells.insert((key: key, value: row.serialize()), at: Int(cursor.cellNum))

        oldNode.cells = Array(allCells[0 ..< LeafNode.leftSplitCount])
        let newParentPageNum: UInt32 = oldNode.isRoot ? 0 : oldNode.parentPageNum
        let newPage = try pager.allocatePage()
        let newNode = LeafNode(
            pageNum: newPage.pageNum,
            isRoot: false,
            parentPageNum: newParentPageNum,
            nextLeafPageNum: oldNextLeaf,
            cells: Array(allCells[LeafNode.leftSplitCount...]),
        )

        oldNode.nextLeafPageNum = newNode.pageNum
        pager.setPage(Int(oldNode.pageNum), data: oldNode.data)
        pager.setPage(Int(newNode.pageNum), data: newNode.data)

        if oldNode.isRoot {
            try createNewRoot(rightChildPageNum: newNode.pageNum)
        } else {
            let parentPageNum = oldNode.parentPageNum
            let newMaxKey = getNodeMaxKey(pageNum: oldNode.pageNum)
            updateInternalNodeKey(pageNum: parentPageNum, oldKey: oldMaxKey, newKey: newMaxKey)
            try internalNodeInsert(parentPageNum: parentPageNum, childPageNum: newNode.pageNum)
        }
    }

    private func getNodeMaxKey(pageNum: UInt32) -> UInt32 {
        switch BTreeNodeFactory.restore(from: try! pager.getPage(Int(pageNum))) {
        case let .leaf(node): node.maxKey
        case let .internal(node): getNodeMaxKey(pageNum: node.rightmostChildPageNum!)
        }
    }

    private func createNewRoot(rightChildPageNum: UInt32) throws(PagerError) {
        let leftChildPage = try pager.allocatePage()
        let leftChildPageNum = leftChildPage.pageNum
        let maxLeftKey = getNodeMaxKey(pageNum: rootPageNum)

        switch BTreeNodeFactory.restore(from: try! pager.getPage(Int(rootPageNum))) {
        case var .leaf(node):
            node.isRoot = false
            node.parentPageNum = rootPageNum
            pager.setPage(Int(leftChildPageNum), data: node.data)
        case var .internal(node):
            node.isRoot = false
            node.parentPageNum = rootPageNum
            pager.setPage(Int(leftChildPageNum), data: node.data)
            for i in 0 ... node.cells.count {
                updateParentPageNum(of: Int(node.childPageNum(at: i)!), to: leftChildPageNum)
            }
        }

        let newRoot = InternalNode(
            pageNum: rootPageNum,
            isRoot: true,
            parentPageNum: 0,
            cells: [(childPageNum: leftChildPageNum, maxKeyInChildPage: maxLeftKey)],
            rightmostChildPageNum: rightChildPageNum,
        )
        pager.setPage(Int(rootPageNum), data: newRoot.data)

        updateParentPageNum(of: Int(rightChildPageNum), to: rootPageNum)
    }

    private func updateParentPageNum(of pageNum: Int, to parentPageNum: UInt32) {
        switch BTreeNodeFactory.restore(from: try! pager.getPage(pageNum)) {
        case var .leaf(node):
            node.parentPageNum = parentPageNum
            pager.setPage(pageNum, data: node.data)
        case var .internal(node):
            node.parentPageNum = parentPageNum
            pager.setPage(pageNum, data: node.data)
        }
    }

    private func updateInternalNodeKey(pageNum: UInt32, oldKey: UInt32, newKey: UInt32) {
        var node = InternalNode.restore(from: try! pager.getPage(Int(pageNum)))
        let cellNum = node.childCellNum(for: oldKey)
        // The rightmost child's max key is not stored in the parent's cells; nothing to update.
        guard cellNum < node.cells.count else { return }
        node.setMaxKeyInChildPage(newKey, at: cellNum)
        pager.setPage(Int(pageNum), data: node.data)
    }

    private func internalNodeInsert(parentPageNum: UInt32, childPageNum: UInt32) throws(PagerError) {
        var parent = InternalNode.restore(from: try! pager.getPage(Int(parentPageNum)))
        let childMaxKey = getNodeMaxKey(pageNum: childPageNum)
        let cellNum = parent.childCellNum(for: childMaxKey)

        if parent.cells.count >= internalNodeMaxCells {
            try internalNodeSplitAndInsert(parentPageNum: parentPageNum, childPageNum: childPageNum)
            return
        }

        guard let rightChildPageNum = parent.rightmostChildPageNum else {
            parent.rightmostChildPageNum = childPageNum
            pager.setPage(Int(parentPageNum), data: parent.data)
            return
        }

        let rightChildMaxKey = getNodeMaxKey(pageNum: rightChildPageNum)
        if childMaxKey > rightChildMaxKey {
            parent.cells.append((childPageNum: rightChildPageNum, maxKeyInChildPage: rightChildMaxKey))
            parent.rightmostChildPageNum = childPageNum
        } else {
            parent.cells.insert((childPageNum: childPageNum, maxKeyInChildPage: childMaxKey), at: cellNum)
        }
        pager.setPage(Int(parentPageNum), data: parent.data)
    }

    private func internalNodeSplitAndInsert(parentPageNum: UInt32, childPageNum: UInt32) throws(PagerError) {
        let oldMax = getNodeMaxKey(pageNum: parentPageNum)
        let childMax = getNodeMaxKey(pageNum: childPageNum)

        // Allocate the new sibling node up front so its pageNum is available throughout.
        let newPage = try pager.allocatePage()
        let newNode = InternalNode(pageNum: newPage.pageNum, isRoot: false, parentPageNum: 0, cells: [], rightmostChildPageNum: nil)
        let newPageNum = newNode.pageNum
        pager.setPage(Int(newPageNum), data: newNode.data)

        let oldNode = InternalNode.restore(from: try! pager.getPage(Int(parentPageNum)))
        let splittingRoot = oldNode.isRoot
        let grandparentPageNum: UInt32
        let actualOldPageNum: UInt32

        if splittingRoot {
            try createNewRoot(rightChildPageNum: newPageNum)
            let rootNode = InternalNode.restore(from: try! pager.getPage(Int(rootPageNum)))
            actualOldPageNum = rootNode.childPageNum(at: 0)!
            grandparentPageNum = rootPageNum
        } else {
            actualOldPageNum = parentPageNum
            grandparentPageNum = oldNode.parentPageNum
        }

        // Move old node's rightmost child into new node
        var actualOldNode = InternalNode.restore(from: try! pager.getPage(Int(actualOldPageNum)))
        let rightChildPageNum = actualOldNode.rightmostChildPageNum!
        try internalNodeInsert(parentPageNum: newPageNum, childPageNum: rightChildPageNum)
        updateParentPageNum(of: Int(rightChildPageNum), to: newPageNum)

        // Invalidate old node's rightmostChildPageNum
        actualOldNode = InternalNode.restore(from: try! pager.getPage(Int(actualOldPageNum)))
        actualOldNode.rightmostChildPageNum = nil
        pager.setPage(Int(actualOldPageNum), data: actualOldNode.data)

        // Move upper half of old node's cells to new node
        for i in stride(from: internalNodeMaxCells - 1, through: internalNodeMaxCells / 2 + 1, by: -1) {
            actualOldNode = InternalNode.restore(from: try! pager.getPage(Int(actualOldPageNum)))
            let childToMovePageNum = actualOldNode.cells[i].childPageNum
            try internalNodeInsert(parentPageNum: newPageNum, childPageNum: childToMovePageNum)
            updateParentPageNum(of: Int(childToMovePageNum), to: newPageNum)

            actualOldNode = InternalNode.restore(from: try! pager.getPage(Int(actualOldPageNum)))
            actualOldNode.cells.removeLast()
            pager.setPage(Int(actualOldPageNum), data: actualOldNode.data)
        }

        // Promote: last remaining cell of old becomes its new rightmostChildPageNum
        actualOldNode = InternalNode.restore(from: try! pager.getPage(Int(actualOldPageNum)))
        let newRightChild = actualOldNode.cells.last!.childPageNum
        actualOldNode.rightmostChildPageNum = newRightChild
        actualOldNode.cells.removeLast()
        pager.setPage(Int(actualOldPageNum), data: actualOldNode.data)

        // Insert new child into whichever node its key belongs to
        let maxAfterSplit = getNodeMaxKey(pageNum: actualOldPageNum)
        let destPageNum = childMax < maxAfterSplit ? actualOldPageNum : newPageNum
        try internalNodeInsert(parentPageNum: destPageNum, childPageNum: childPageNum)
        updateParentPageNum(of: Int(childPageNum), to: destPageNum)

        // Update grandparent's key for old node
        updateInternalNodeKey(pageNum: grandparentPageNum, oldKey: oldMax,
                              newKey: getNodeMaxKey(pageNum: actualOldPageNum))

        // If not root split, insert new node into grandparent
        if !splittingRoot {
            try internalNodeInsert(parentPageNum: grandparentPageNum, childPageNum: newPageNum)
            updateParentPageNum(of: Int(newPageNum), to: grandparentPageNum)
        }
    }
}
