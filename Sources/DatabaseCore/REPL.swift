import Foundation

enum MetaCommand: Equatable {
    case exit
    case constants
    case btree
    case unrecognized(String)

    init?(_ input: String) {
        guard input.hasPrefix(".") else { return nil }
        switch input {
        case ".exit": self = .exit
        case ".constants": self = .constants
        case ".btree": self = .btree
        default: self = .unrecognized(input)
        }
    }

    func execute(table: Table) -> Bool {
        switch self {
        case .exit:
            return true
        case .constants:
            print("Constants:")
            print("ROW_SIZE: \(Row.size)")
            print("COMMON_NODE_HEADER_SIZE: \(LeafNode.commonNodeHeaderSize)")
            print("LEAF_NODE_HEADER_SIZE: \(LeafNode.headerSize)")
            print("LEAF_NODE_CELL_SIZE: \(LeafNode.cellSize)")
            print("LEAF_NODE_SPACE_FOR_CELLS: \(LeafNode.spaceForCells)")
            print("LEAF_NODE_MAX_CELLS: \(LeafNode.maxCells)")
            return false
        case .btree:
            print("Tree:")
            table.btree.printTree()
            return false
        case let .unrecognized(cmd):
            print("Unrecognized command '\(cmd)'.")
            return false
        }
    }
}

public struct REPL {
    public init() {}

    private func printPrompt() {
        print("db > ", terminator: "")
    }

    public func run(filename: String) throws {
        let table = try Table(filename: filename)
        defer { table.close() }
        while true {
            printPrompt()
            guard let line = readLine() else { break }

            if let cmd = MetaCommand(line) {
                if cmd.execute(table: table) { break }
                continue
            }

            switch Statement.parse(line) {
            case let .success(statement):
                do {
                    try statement.execute(on: table)
                    print("Executed.")
                } catch ExecuteError.duplicateKey {
                    print("Error: Duplicate key.")
                } catch ExecuteError.tableFull {
                    print("Error: Table full.")
                }
            case .failure(.syntaxError):
                print("Syntax error. Could not parse statement.")
            case .failure(.negativeId):
                print("ID must be positive.")
            case .failure(.stringTooLong):
                print("String is too long.")
            case .failure(.unrecognized):
                print("Unrecognized keyword at start of '\(line)'.")
            }
        }
    }
}
