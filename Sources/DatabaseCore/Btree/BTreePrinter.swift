import Foundation

struct BTreePrinter {
    private let pager: Pager

    init(pager: Pager) {
        self.pager = pager
    }

    func printTree(pageNum: UInt32 = 0, indentation: Int = 0) {
        let indent = String(repeating: "  ", count: indentation)
        switch BTreeNodeFactory.restore(from: try! pager.getPage(Int(pageNum))) {
        case let .leaf(node):
            print("\(indent)- leaf (size \(node.cells.count))")
            for i in 0 ..< node.cells.count {
                print("\(indent)  - \(node.key(at: i))")
            }
        case let .internal(node):
            print("\(indent)- internal (size \(node.cells.count))")
            for i in 0 ..< node.cells.count {
                let childPageNum = node.childPageNum(at: i)!
                printTree(pageNum: childPageNum, indentation: indentation + 1)
                print("\(indent)  - key \(node.key(at: i))")
            }
            printTree(pageNum: node.rightmostChildPageNum!, indentation: indentation + 1)
        }
    }
}
