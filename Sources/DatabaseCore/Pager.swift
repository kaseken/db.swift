import Foundation

struct Page {
    let pageNum: UInt32
    let data: Data
}

enum PagerError: Error, Equatable {
    case cannotOpenFile(String)
    case tableFull
    case pageNotAllocated(Int)
}

class Pager {
    private static let maxPages = 100
    static let pageSize = 4096

    private let fileHandle: FileHandle
    /// The file size at the time this Pager was opened. Used only during cache-miss
    /// to determine whether a page already exists on disk or needs to be freshly allocated.
    private let diskFileLength: Int
    /// The number of pages allocated so far.
    private(set) var numPages: Int
    private var pages: [Data?]

    init(filename: String) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: filename) {
            fm.createFile(atPath: filename, contents: nil)
        }
        guard let fh = FileHandle(forUpdatingAtPath: filename) else {
            throw PagerError.cannotOpenFile(filename)
        }
        fileHandle = fh
        diskFileLength = Int(fh.seekToEndOfFile())
        numPages = diskFileLength / Pager.pageSize
        pages = Array(repeating: nil, count: Pager.maxPages)
    }

    func getPage(_ pageNum: Int) throws(PagerError) -> Page {
        if let cached = pages[pageNum] {
            return Page(pageNum: UInt32(pageNum), data: cached)
        }
        // Pages are stored sequentially in the file: page 0 at offset 0, page 1 at offset 4096, etc.
        let pageOffset = pageNum * Pager.pageSize
        guard pageOffset < diskFileLength else {
            throw PagerError.pageNotAllocated(pageNum)
        }
        fileHandle.seek(toFileOffset: UInt64(pageOffset))
        // For full pages this equals pageSize; for the last partial page it is smaller
        let bytesToRead = min(Pager.pageSize, diskFileLength - pageOffset)
        var data = fileHandle.readData(ofLength: bytesToRead)
        // Pad the last partial page with zeros so every cached page is always pageSize bytes
        if data.count < Pager.pageSize {
            data.append(Data(count: Pager.pageSize - data.count))
        }
        pages[pageNum] = data
        return Page(pageNum: UInt32(pageNum), data: data)
    }

    func setPage(_ pageNum: Int, data: Data) {
        pages[pageNum] = data
    }

    func allocatePage() throws(PagerError) -> Page {
        guard numPages < Pager.maxPages else { throw .tableFull }
        let pageNum = numPages
        numPages += 1
        let data = Data(count: Pager.pageSize)
        pages[pageNum] = data
        return Page(pageNum: UInt32(pageNum), data: data)
    }

    func flushAll() {
        for i in 0 ..< numPages {
            flush(pageNum: i, numBytes: Pager.pageSize)
        }
    }

    private func flush(pageNum: Int, numBytes: Int) {
        guard let page = pages[pageNum] else { return }
        fileHandle.seek(toFileOffset: UInt64(pageNum * Pager.pageSize))
        fileHandle.write(page.prefix(numBytes))
    }

    func close() {
        fileHandle.closeFile()
    }
}
