import Foundation

enum MetaCommandResult {
    case exit
    case unrecognizedCommand
}

func printPrompt() {
    FileHandle.standardOutput.write(Data("db > ".utf8))
}

func doMetaCommand(_ input: String) -> MetaCommandResult {
    if input == ".exit" { return .exit }
    return .unrecognizedCommand
}

repl: while true {
    printPrompt()
    guard let line = readLine() else { break }

    if line.hasPrefix(".") {
        switch doMetaCommand(line) {
        case .exit:
            break repl
        case .unrecognizedCommand:
            print("Unrecognized command '\(line)'.")
        }
        continue
    }

    print("Unrecognized keyword at start of '\(line)'.")
}
