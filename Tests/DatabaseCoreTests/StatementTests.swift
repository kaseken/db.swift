@testable import DatabaseCore
import Testing

struct StatementTests {
    @Test func `insert keyword`() {
        #expect(Statement("insert 1 foo foo@example.com") == .insert)
    }

    @Test func `select keyword`() {
        #expect(Statement("select") == .select)
    }

    @Test func `unknown keyword`() {
        #expect(Statement("unknown") == nil)
    }

    @Test func `empty input`() {
        #expect(Statement("") == nil)
    }
}
