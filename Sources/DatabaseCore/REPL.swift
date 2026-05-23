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
        // Use write() to avoid newline that print() appends
        FileHandle.standardOutput.write(Data("db > ".utf8))
    }

    public func run() {
        while true {
            printPrompt()
            guard let line = readLine() else { break }

            if let cmd = MetaCommand(line) {
                cmd.execute()
                continue
            }

            if let statement = Statement(line) {
                statement.execute()
            } else {
                print("Unrecognized keyword at start of '\(line)'.")
            }
        }
    }
}
