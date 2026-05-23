import Foundation

enum PagerError: Error {
    case cannotOpenFile(String)
}

class Pager {
    static let maxPages = 100
    static let pageSize = 4096

    private let fileHandle: FileHandle
    /// The file size at the time this Pager was opened. Used only during cache-miss
    /// to determine whether a page already exists on disk or needs to be freshly allocated.
    let diskFileLength: Int
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
        pages = Array(repeating: nil, count: Pager.maxPages)
    }

    func getPage(_ pageNum: Int) -> Data {
        if let cached = pages[pageNum] {
            return cached
        }
        // Pages are stored sequentially in the file: page 0 at offset 0, page 1 at offset 4096, etc.
        let pageOffset = pageNum * Pager.pageSize
        guard pageOffset < diskFileLength else {
            // Page is beyond the end of the file — allocate a blank page
            let page = Data(count: Pager.pageSize)
            pages[pageNum] = page
            return page
        }
        fileHandle.seek(toFileOffset: UInt64(pageOffset))
        // For full pages this equals pageSize; for the last partial page it is smaller
        let bytesToRead = min(Pager.pageSize, diskFileLength - pageOffset)
        var page = fileHandle.readData(ofLength: bytesToRead)
        // Pad the last partial page with zeros so every cached page is always pageSize bytes
        if page.count < Pager.pageSize {
            page.append(Data(count: Pager.pageSize - page.count))
        }
        pages[pageNum] = page
        return page
    }

    func setPage(_ pageNum: Int, data: Data) {
        pages[pageNum] = data
    }

    func flush(pageNum: Int, numBytes: Int) {
        guard let page = pages[pageNum] else {
            return
        }
        fileHandle.seek(toFileOffset: UInt64(pageNum * Pager.pageSize))
        fileHandle.write(page.prefix(numBytes))
    }

    func close() {
        fileHandle.closeFile()
    }
}
