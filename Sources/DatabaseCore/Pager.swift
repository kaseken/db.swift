import Foundation

enum PagerError: Error {
    case cannotOpenFile(String)
}

class Pager {
    static let maxPages = 100
    static let pageSize = 4096

    private let fileHandle: FileHandle
    let fileLength: Int
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
        fileLength = Int(fh.seekToEndOfFile())
        pages = Array(repeating: nil, count: Pager.maxPages)
    }

    func getPage(_ pageNum: Int) -> Data {
        if pages[pageNum] == nil {
            let pageOffset = pageNum * Pager.pageSize
            if pageOffset < fileLength {
                fileHandle.seek(toFileOffset: UInt64(pageOffset))
                let bytesToRead = min(Pager.pageSize, fileLength - pageOffset)
                var page = fileHandle.readData(ofLength: bytesToRead)
                if page.count < Pager.pageSize {
                    page.append(Data(count: Pager.pageSize - page.count))
                }
                pages[pageNum] = page
            } else {
                pages[pageNum] = Data(count: Pager.pageSize)
            }
        }
        return pages[pageNum]!
    }

    func setPage(_ pageNum: Int, data: Data) {
        pages[pageNum] = data
    }

    func flush(pageNum: Int, numBytes: Int) {
        guard pages[pageNum] != nil else { return }
        fileHandle.seek(toFileOffset: UInt64(pageNum * Pager.pageSize))
        fileHandle.write(pages[pageNum]!.prefix(numBytes))
    }

    func close() {
        fileHandle.closeFile()
    }
}
