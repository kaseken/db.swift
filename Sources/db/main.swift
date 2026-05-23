import DatabaseCore
import Foundation

guard CommandLine.arguments.count >= 2 else {
    print("Must supply a database filename.")
    Foundation.exit(1)
}

let filename = CommandLine.arguments[1]
try REPL().run(filename: filename)
