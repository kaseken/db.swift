@testable import DatabaseCore
import Testing

struct StatementTests {
    @Test func `insert parses valid input`() {
        guard case let .success(stmt) = Statement.prepare("insert 1 foo foo@example.com"),
              case let .insert(row) = stmt
        else {
            Issue.record("Expected .success(.insert(...))")
            return
        }
        #expect(row == Row(id: 1, username: "foo", email: "foo@example.com"))
    }

    @Test func `select keyword`() {
        guard case let .success(stmt) = Statement.prepare("select"),
              case .select = stmt
        else {
            Issue.record("Expected .success(.select)")
            return
        }
    }

    @Test func `insert with missing args returns syntax error`() {
        guard case let .failure(err) = Statement.prepare("insert") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .syntaxError)
    }

    @Test func `insert with non-numeric id returns syntax error`() {
        guard case let .failure(err) = Statement.prepare("insert abc foo foo@example.com") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .syntaxError)
    }

    @Test func `unknown keyword returns unrecognized`() {
        guard case let .failure(err) = Statement.prepare("unknown") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .unrecognized)
    }

    @Test func `empty input returns unrecognized`() {
        guard case let .failure(err) = Statement.prepare("") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .unrecognized)
    }
}
