import Foundation

enum MetaCommand: Equatable {
    case exit
    case unrecognized(String)

    init?(_ input: String) {
        guard input.hasPrefix(".") else { return nil }
        switch input {
        case ".exit": self = .exit
        default: self = .unrecognized(input)
        }
    }

    /// Returns true if the REPL should exit.
    func execute() -> Bool {
        switch self {
        case .exit:
            return true
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
                if cmd.execute() { break }
                continue
            }

            switch Statement.prepare(line) {
            case let .success(statement):
                switch statement.execute(on: table) {
                case .success: print("Executed.")
                case .tableFull: print("Error: Table full.")
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
