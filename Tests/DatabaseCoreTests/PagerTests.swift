@testable import DatabaseCore
import Foundation
import Testing

struct PagerTests {
    private func makeTempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
            .path
    }

    @Test func `opens a new file with zero pages`() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pager = try Pager(filename: path)
        defer { pager.close() }
        #expect(pager.numPages == 0)
    }

    @Test func `getPage returns a blank page after allocatePage`() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pager = try Pager(filename: path)
        defer { pager.close() }
        let page = try pager.allocatePage()
        let fetched = try pager.getPage(Int(page.pageNum))
        #expect(fetched.data == Data(count: Pager.pageSize))
    }

    @Test func `getPage returns cached page on second call`() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pager = try Pager(filename: path)
        defer { pager.close() }
        let page = try pager.allocatePage()
        var data = try pager.getPage(Int(page.pageNum)).data
        data[0] = 0xFF
        pager.setPage(Int(page.pageNum), data: data)
        // Second call should return the cached (modified) page, not a fresh blank one
        #expect(try pager.getPage(Int(page.pageNum)).data[0] == 0xFF)
    }

    @Test func `flushAll persists data that can be read back after reopening`() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        var pageData = Data(count: Pager.pageSize)
        pageData[0] = 0x42
        let pager = try Pager(filename: path)
        _ = try pager.allocatePage()
        pager.setPage(0, data: pageData)
        pager.flushAll()
        pager.close()

        let pager2 = try Pager(filename: path)
        defer { pager2.close() }
        #expect(pager2.numPages == 1)
        #expect(try pager2.getPage(0).data[0] == 0x42)
    }

    @Test func `flushAll on empty pager does not write to file`() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pager = try Pager(filename: path)
        pager.flushAll()
        pager.close()
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        #expect(fileSize == 0)
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
        let page = try pager.getPage(0)

        #expect(page.data.count == Pager.pageSize)
        #expect(page.data[0] == 0xAB)
        // Bytes beyond the original partial data must be zero-padded.
        #expect(page.data[partialSize] == 0x00)
        #expect(page.data[Pager.pageSize - 1] == 0x00)
    }

    @Test func `getPage throws pageNotAllocated for unallocated page`() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pager = try Pager(filename: path)
        defer { pager.close() }
        #expect(throws: PagerError.pageNotAllocated(0)) {
            try pager.getPage(0)
        }
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
