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

    func execute() {
        switch self {
        case .exit:
            Foundation.exit(0)
        case let .unrecognized(cmd):
            print("Unrecognized command '\(cmd)'.")
        }
    }
}

public struct REPL {
    public init() {}

    private func printPrompt() {
        FileHandle.standardOutput.write(Data("db > ".utf8))
    }

    public func run() {
        let table = Table()
        while true {
            printPrompt()
            guard let line = readLine() else { break }

            if let cmd = MetaCommand(line) {
                cmd.execute()
                continue
            }

            switch Statement.prepare(line) {
            case let .success(statement):
                switch statement.execute(on: table) {
                case .success: break
                case .tableFull: print("Error: Table full.")
                }
            case .failure(.syntaxError):
                print("Syntax error. Could not parse statement.")
            case .failure(.unrecognized):
                print("Unrecognized keyword at start of '\(line)'.")
            }
        }
    }
}
