import Foundation

enum NodeType: UInt8 {
    case `internal` = 0
    case leaf = 1
}

/// Byte offsets and sizes of the common node header.
enum BTreeNodeLayout {
    static let nodeTypeOffset = 0
    static let isRootOffset = 1
    static let parentPointerOffset = 2
    static let headerSize = 6
}

// MARK: - BTreeNodeFactory

enum BTreeNodeFactory {
    case leaf(LeafNode)
    case `internal`(InternalNode)

    static func restore(from page: Page) -> BTreeNodeFactory {
        switch NodeType(rawValue: page.data[BTreeNodeLayout.nodeTypeOffset])! {
        case .leaf: .leaf(LeafNode.restore(from: page))
        case .internal: .internal(InternalNode.restore(from: page))
        }
    }
}

// MARK: - BTreeNode protocol

protocol BTreeNode {
    var nodeType: NodeType { get }
    var isRoot: Bool { get set }
    var parentPageNum: UInt32 { get set }
    /// In-memory only. Not serialized into `data`.
    var pageNum: UInt32 { get }
    /// Serialized page representation, ready to write to the Pager.
    var data: Data { get }
}
