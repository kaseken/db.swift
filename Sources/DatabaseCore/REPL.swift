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

    func execute(table: Table) {
        switch self {
        case .exit:
            table.close()
            Foundation.exit(0)
        case let .unrecognized(cmd):
            print("Unrecognized command '\(cmd)'.")
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
        while true {
            printPrompt()
            guard let line = readLine() else {
                table.close()
                break
            }

            if let cmd = MetaCommand(line) {
                cmd.execute(table: table)
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
