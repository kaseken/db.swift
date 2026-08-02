import Foundation

enum MetaCommand: Equatable {
    case exit
    case btree
    case unrecognized(String)

    init?(_ input: String) {
        guard input.hasPrefix(".") else { return nil }
        switch input {
        case ".exit": self = .exit
        case ".btree": self = .btree
        default: self = .unrecognized(input)
        }
    }

    func execute(table: Table) -> Bool {
        switch self {
        case .exit:
            return true
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
        // Only show the prompt when stdin is a terminal, mirroring real RDB CLIs
        // (e.g. sqlite3), which stay silent when reading piped input.
        let isInteractive = isatty(FileHandle.standardInput.fileDescriptor) != 0
        while true {
            if isInteractive { printPrompt() }
            guard let line = readLine() else { break }

            if let cmd = MetaCommand(line) {
                if cmd.execute(table: table) { break }
                continue
            }

            switch Parser.parse(line) {
            case let .success(statement):
                do {
                    try table.execute(statement)
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
