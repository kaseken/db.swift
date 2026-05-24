@testable import DatabaseCore
import Foundation
import Testing

struct PagerTests {
    private func makeTempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
            .path
    }

    @Test func `opens a new file with diskFileLength zero`() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pager = try Pager(filename: path)
        defer { pager.close() }
        #expect(pager.diskFileLength == 0)
    }

    @Test func `getPage returns a blank page for a new file`() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pager = try Pager(filename: path)
        defer { pager.close() }
        let page = pager.getPage(0)
        #expect(page == Data(count: Pager.pageSize))
    }

    @Test func `getPage returns cached page on second call`() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pager = try Pager(filename: path)
        defer { pager.close() }
        var page = pager.getPage(0)
        page[0] = 0xFF
        pager.setPage(0, data: page)
        // Second call should return the cached (modified) page, not a fresh blank one
        #expect(pager.getPage(0)[0] == 0xFF)
    }

    @Test func `flush persists data that can be read back after reopening`() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        var page = Data(count: Pager.pageSize)
        page[0] = 0x42
        let pager = try Pager(filename: path)
        pager.setPage(0, data: page)
        pager.flush(pageNum: 0, numBytes: Pager.pageSize)
        pager.close()

        let pager2 = try Pager(filename: path)
        defer { pager2.close() }
        #expect(pager2.diskFileLength == Pager.pageSize)
        #expect(pager2.getPage(0)[0] == 0x42)
    }

    @Test func `flush on uncached page does not write to file`() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pager = try Pager(filename: path)
        defer { pager.close() }
        pager.flush(pageNum: 0, numBytes: Pager.pageSize)
        #expect(pager.diskFileLength == 0)
    }

    @Test func `getPage zero-pads a partial page read from disk`() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Write fewer than pageSize bytes directly to the file to simulate a partial page.
        let partialSize = 16
        var partial = Data(count: partialSize)
        partial[0] = 0xAB
        FileManager.default.createFile(atPath: path, contents: partial)

        let pager = try Pager(filename: path)
        defer { pager.close() }
        let page = pager.getPage(0)

        #expect(page.count == Pager.pageSize)
        #expect(page[0] == 0xAB)
        // Bytes beyond the original partial data must be zero-padded.
        #expect(page[partialSize] == 0x00)
        #expect(page[Pager.pageSize - 1] == 0x00)
    }

    @Test func `throws cannotOpenFile when file is not readable`() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
            .path
        FileManager.default.createFile(atPath: path, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
            try? FileManager.default.removeItem(atPath: path)
        }

        #expect {
            try Pager(filename: path)
        } throws: { error in
            guard case PagerError.cannotOpenFile(path) = error else {
                return false
            }
            return true
        }
    }
}
