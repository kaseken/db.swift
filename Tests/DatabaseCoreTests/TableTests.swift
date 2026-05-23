@testable import DatabaseCore
import Testing

struct TableTests {
    @Test func `insert and select one row`() {
        let table = Table()
        let row = Row(id: 1, username: "cstack", email: "foo@example.com")
        #expect(table.insert(row: row) == .success)
        #expect(table.select() == [row])
    }

    @Test func `insert and select two rows`() {
        let table = Table()
        let row1 = Row(id: 1, username: "cstack", email: "foo@example.com")
        let row2 = Row(id: 2, username: "bob", email: "bob@example.com")
        table.insert(row: row1)
        table.insert(row: row2)
        #expect(table.select() == [row1, row2])
    }

    @Test func `table full error`() {
        let table = Table()
        for i in 0 ..< Table.maxRows {
            let row = Row(id: UInt32(i), username: "u", email: "e@example.com")
            #expect(table.insert(row: row) == .success)
        }
        let extra = Row(id: 9999, username: "over", email: "over@example.com")
        #expect(table.insert(row: extra) == .tableFull)
    }
}
