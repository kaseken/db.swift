import Foundation
import Testing

struct REPLIntegrationTests {
    private static let binaryURL: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        let packageRoot = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot.appendingPathComponent(".build/debug/db")
    }()

    private func runScript(_ commands: [String]) throws -> [String] {
        let process = Process()
        process.executableURL = Self.binaryURL

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe

        try process.run()

        let input = (commands + [".exit"]).joined(separator: "\n") + "\n"
        stdinPipe.fileHandleForWriting.write(Data(input.utf8))
        stdinPipe.fileHandleForWriting.closeFile()

        let output = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8,
        ) ?? ""
        process.waitUntilExit()

        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    @Test func `inserts and retrieves a row`() throws {
        let result = try runScript([
            "insert 1 user1 person1@example.com",
            "select",
        ])
        #expect(result == [
            "db > Executed.",
            "db > (1, user1, person1@example.com)",
            "Executed.",
            "db > ",
        ])
    }

    @Test func `allows inserting strings that are the maximum length`() throws {
        let longUsername = String(repeating: "a", count: 32)
        let longEmail = String(repeating: "a", count: 255)
        let result = try runScript([
            "insert 1 \(longUsername) \(longEmail)",
            "select",
        ])
        #expect(result == [
            "db > Executed.",
            "db > (1, \(longUsername), \(longEmail))",
            "Executed.",
            "db > ",
        ])
    }

    @Test func `prints an error message if strings are too long`() throws {
        let longUsername = String(repeating: "a", count: 33)
        let result = try runScript([
            "insert 1 \(longUsername) foo@bar.com",
            "insert 2 foo foo@bar.com",
        ])
        #expect(result == [
            "db > String is too long.",
            "db > Executed.",
            "db > ",
        ])
    }

    @Test func `prints an error message if id is negative`() throws {
        let result = try runScript([
            "insert -1 foo foo@example.com",
            "insert 1 foo foo@example.com",
        ])
        #expect(result == [
            "db > ID must be positive.",
            "db > Executed.",
            "db > ",
        ])
    }

    @Test func `prints error message for unrecognized meta command`() throws {
        let result = try runScript([".unknown"])
        #expect(result == [
            "db > Unrecognized command '.unknown'.",
            "db > ",
        ])
    }

    @Test func `prints error message for syntax error`() throws {
        let result = try runScript(["insert foo"])
        #expect(result == [
            "db > Syntax error. Could not parse statement.",
            "db > ",
        ])
    }

    @Test func `prints error message for unrecognized keyword`() throws {
        let result = try runScript(["unknown"])
        #expect(result == [
            "db > Unrecognized keyword at start of 'unknown'.",
            "db > ",
        ])
    }

    @Test func `prints error message when table is full`() throws {
        let inserts = (1 ... 1401).map { "insert \($0) user\($0) person\($0)@example.com" }
        let result = try runScript(inserts)
        #expect(result.suffix(2) == [
            "db > Error: Table full.",
            "db > ",
        ])
    }
}
