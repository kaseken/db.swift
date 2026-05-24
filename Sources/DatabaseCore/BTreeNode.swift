import Foundation

enum NodeType: UInt8 {
    case `internal` = 0
    case leaf = 1
}

enum LeafNode {
    // Common node header layout
    static let nodeTypeSize = 1
    static let nodeTypeOffset = 0
    static let isRootSize = 1
    static let isRootOffset = 1
    static let parentPointerSize = 4
    static let parentPointerOffset = 2
    static let commonNodeHeaderSize = 6

    // Leaf node header layout
    static let numCellsSize = 4
    static let numCellsOffset = commonNodeHeaderSize
    static let headerSize = commonNodeHeaderSize + numCellsSize // 10

    // Leaf node body layout
    static let keySize = 4
    static let valueSize = Row.size // 291
    static let cellSize = keySize + valueSize // 295
    static let spaceForCells = Pager.pageSize - headerSize // 4086
    static let maxCells = spaceForCells / cellSize // 13

    static func initialize() -> Data {
        var page = Data(count: Pager.pageSize)
        page[nodeTypeOffset] = NodeType.leaf.rawValue
        // numCells is already 0 from zero-initialized Data
        return page
    }

    static func numCells(_ page: Data) -> UInt32 {
        page.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: numCellsOffset, as: UInt32.self)
        }
    }

    static func setNumCells(_ page: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value) { src in
            page.replaceSubrange(numCellsOffset ..< numCellsOffset + numCellsSize, with: src)
        }
    }

    static func cellOffset(cellNum: Int) -> Int {
        headerSize + cellNum * cellSize
    }

    static func keyOffset(cellNum: Int) -> Int {
        cellOffset(cellNum: cellNum)
    }

    static func valueOffset(cellNum: Int) -> Int {
        cellOffset(cellNum: cellNum) + keySize
    }

    static func key(_ page: Data, cellNum: Int) -> UInt32 {
        page.withUnsafeBytes { ptr in
            ptr.baseAddress!.loadUnaligned(fromByteOffset: keyOffset(cellNum: cellNum), as: UInt32.self)
        }
    }

    static func setKey(_ page: inout Data, cellNum: Int, key: UInt32) {
        withUnsafeBytes(of: key) { src in
            let off = keyOffset(cellNum: cellNum)
            page.replaceSubrange(off ..< off + keySize, with: src)
        }
    }
}
