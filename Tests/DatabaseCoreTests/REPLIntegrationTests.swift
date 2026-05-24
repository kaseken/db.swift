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

    private func makeTempDBPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
            .path
    }

    private func runScript(_ commands: [String], dbFile: String) throws -> [String] {
        let process = Process()
        process.executableURL = Self.binaryURL
        process.arguments = [dbFile]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe

        try process.run()

        if !commands.isEmpty {
            let input = commands.joined(separator: "\n") + "\n"
            stdinPipe.fileHandleForWriting.write(Data(input.utf8))
        }
        stdinPipe.fileHandleForWriting.closeFile()

        let output = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8,
        ) ?? ""
        process.waitUntilExit()

        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    @Test func `inserts and retrieves a row`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let result = try runScript([
            "insert 1 user1 person1@example.com",
            "select",
            ".exit",
        ], dbFile: db)
        #expect(result == [
            "db > Executed.",
            "db > (1, user1, person1@example.com)",
            "Executed.",
            "db > ",
        ])
    }

    @Test func `allows inserting strings that are the maximum length`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let longUsername = String(repeating: "a", count: 32)
        let longEmail = String(repeating: "a", count: 255)
        let result = try runScript([
            "insert 1 \(longUsername) \(longEmail)",
            "select",
            ".exit",
        ], dbFile: db)
        #expect(result == [
            "db > Executed.",
            "db > (1, \(longUsername), \(longEmail))",
            "Executed.",
            "db > ",
        ])
    }

    @Test func `prints an error message if strings are too long`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let longUsername = String(repeating: "a", count: 33)
        let result = try runScript([
            "insert 1 \(longUsername) foo@bar.com",
            "insert 2 foo foo@bar.com",
            ".exit",
        ], dbFile: db)
        #expect(result == [
            "db > String is too long.",
            "db > Executed.",
            "db > ",
        ])
    }

    @Test func `prints an error message if id is negative`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let result = try runScript([
            "insert -1 foo foo@example.com",
            "insert 1 foo foo@example.com",
            ".exit",
        ], dbFile: db)
        #expect(result == [
            "db > ID must be positive.",
            "db > Executed.",
            "db > ",
        ])
    }

    @Test func `prints error message for unrecognized meta command`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let result = try runScript([".unknown", ".exit"], dbFile: db)
        #expect(result == [
            "db > Unrecognized command '.unknown'.",
            "db > ",
        ])
    }

    @Test func `prints error message for syntax error`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let result = try runScript(["insert foo", ".exit"], dbFile: db)
        #expect(result == [
            "db > Syntax error. Could not parse statement.",
            "db > ",
        ])
    }

    @Test func `prints error message for unrecognized keyword`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let result = try runScript(["unknown", ".exit"], dbFile: db)
        #expect(result == [
            "db > Unrecognized keyword at start of 'unknown'.",
            "db > ",
        ])
    }

    @Test func `exits gracefully on EOF`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let result = try runScript([], dbFile: db)
        #expect(result == ["db > "])
    }

    @Test func `allows printing out the structure of a one-node btree`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let result = try runScript([
            "insert 3 user3 person3@example.com",
            "insert 1 user1 person1@example.com",
            "insert 2 user2 person2@example.com",
            ".btree",
            ".exit",
        ], dbFile: db)
        #expect(result == [
            "db > Executed.",
            "db > Executed.",
            "db > Executed.",
            "db > Tree:",
            "- leaf (size 3)",
            "  - 1",
            "  - 2",
            "  - 3",
            "db > ",
        ])
    }

    @Test func `allows printing out the structure of a 3-leaf-node btree`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let inserts = (1 ... 14).map { "insert \($0) user\($0) person\($0)@example.com" }
        let result = try runScript(
            inserts + [".btree", "insert 15 user15 person15@example.com", ".exit"],
            dbFile: db,
        )
        #expect(Array(result.dropFirst(14)) == [
            "db > Tree:",
            "- internal (size 1)",
            "  - leaf (size 7)",
            "    - 1", "    - 2", "    - 3", "    - 4", "    - 5", "    - 6", "    - 7",
            "  - key 7",
            "  - leaf (size 7)",
            "    - 8", "    - 9", "    - 10", "    - 11", "    - 12", "    - 13", "    - 14",
            "db > Executed.",
            "db > ",
        ])
    }

    @Test func `splits correctly when new cell lands in the left node`() throws {
        // Insert 1-6 and 8-14 first, then insert 7 last.
        // cursor.cellNum for key 7 is 6, which is < leftSplitCount (7),
        // so the new cell is written into the left (old) page — the branch not covered by sequential inserts.
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let insertsWithout7 = (1 ... 14).filter { $0 != 7 }.map { "insert \($0) user\($0) person\($0)@example.com" }
        let result = try runScript(
            insertsWithout7 + ["insert 7 user7 person7@example.com", ".btree", ".exit"],
            dbFile: db,
        )
        #expect(Array(result.dropFirst(14)) == [
            "db > Tree:",
            "- internal (size 1)",
            "  - leaf (size 7)",
            "    - 1", "    - 2", "    - 3", "    - 4", "    - 5", "    - 6", "    - 7",
            "  - key 7",
            "  - leaf (size 7)",
            "    - 8", "    - 9", "    - 10", "    - 11", "    - 12", "    - 13", "    - 14",
            "db > ",
        ])
    }

    @Test func `prints error when inserting duplicate key`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let result = try runScript([
            "insert 1 user1 person1@example.com",
            "insert 1 user1 person1@example.com",
            ".exit",
        ], dbFile: db)
        #expect(result == [
            "db > Executed.",
            "db > Error: Duplicate key.",
            "db > ",
        ])
    }

    @Test func `allows printing out the structure of a 3-leaf-node btree after non-root split`() throws {
        // 21 rows: root split at row 14, then non-root split at row 21 → internal (size 2), 3 leaves
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let inserts = (1 ... 21).map { "insert \($0) user\($0) person\($0)@example.com" }
        let result = try runScript(inserts + [".btree", ".exit"], dbFile: db)
        #expect(Array(result.dropFirst(21)) == [
            "db > Tree:",
            "- internal (size 2)",
            "  - leaf (size 7)",
            "    - 1", "    - 2", "    - 3", "    - 4", "    - 5", "    - 6", "    - 7",
            "  - key 7",
            "  - leaf (size 7)",
            "    - 8", "    - 9", "    - 10", "    - 11", "    - 12", "    - 13", "    - 14",
            "  - key 14",
            "  - leaf (size 7)",
            "    - 15", "    - 16", "    - 17", "    - 18", "    - 19", "    - 20", "    - 21",
            "db > ",
        ])
    }

    @Test func `prints constants`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }
        let result = try runScript([".constants", ".exit"], dbFile: db)
        #expect(result == [
            "db > Constants:",
            "ROW_SIZE: 291",
            "COMMON_NODE_HEADER_SIZE: 6",
            "LEAF_NODE_HEADER_SIZE: 14",
            "LEAF_NODE_CELL_SIZE: 295",
            "LEAF_NODE_SPACE_FOR_CELLS: 4082",
            "LEAF_NODE_MAX_CELLS: 13",
            "db > ",
        ])
    }

    @Test func `persists data across sessions`() throws {
        let db = makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: db) }

        // First session: insert rows
        _ = try runScript([
            "insert 1 user1 person1@example.com",
            "insert 2 user2 person2@example.com",
            ".exit",
        ], dbFile: db)

        // Second session: data should still be there
        let result = try runScript(["select", ".exit"], dbFile: db)
        #expect(result == [
            "db > (1, user1, person1@example.com)",
            "(2, user2, person2@example.com)",
            "Executed.",
            "db > ",
        ])
    }
}
