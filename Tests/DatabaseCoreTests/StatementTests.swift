import Testing
@testable import DatabaseCore

@Suite struct StatementTests {
    @Test func insertKeyword() {
        #expect(Statement("insert 1 foo foo@example.com") == .insert)
    }

    @Test func selectKeyword() {
        #expect(Statement("select") == .select)
    }

    @Test func unknownKeyword() {
        #expect(Statement("unknown") == nil)
    }

    @Test func emptyInput() {
        #expect(Statement("") == nil)
    }
}
