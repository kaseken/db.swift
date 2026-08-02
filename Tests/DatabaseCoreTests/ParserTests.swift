@testable import DatabaseCore
import Testing

struct ParserTests {
    @Test func `insert parses valid input`() {
        guard case let .success(stmt) = Parser.parse("INSERT INTO users VALUES (1, 'foo', 'foo@example.com')"),
              case let .insert(row) = stmt
        else {
            Issue.record("Expected .success(.insert(...))")
            return
        }
        #expect(row == Row(id: 1, username: "foo", email: "foo@example.com"))
    }

    @Test func `select keyword`() {
        guard case let .success(stmt) = Parser.parse("SELECT * FROM users"),
              case .select = stmt
        else {
            Issue.record("Expected .success(.select)")
            return
        }
    }

    @Test func `keywords are case-insensitive`() {
        guard case let .success(stmt) = Parser.parse("select * from users"),
              case .select = stmt
        else {
            Issue.record("Expected .success(.select)")
            return
        }
    }

    @Test func `insert with missing args returns syntax error`() {
        guard case let .failure(err) = Parser.parse("INSERT INTO users VALUES (1)") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .syntaxError)
    }

    @Test func `insert with non-numeric id returns syntax error`() {
        guard case let .failure(err) = Parser.parse("INSERT INTO users VALUES ('abc', 'foo', 'foo@example.com')") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .syntaxError)
    }

    @Test func `insert into unknown table returns syntax error`() {
        guard case let .failure(err) = Parser.parse("INSERT INTO other VALUES (1, 'foo', 'foo@example.com')") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .syntaxError)
    }

    @Test func `select from unknown table returns syntax error`() {
        guard case let .failure(err) = Parser.parse("SELECT * FROM other") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .syntaxError)
    }

    @Test func `unterminated string returns syntax error`() {
        guard case let .failure(err) = Parser.parse("INSERT INTO users VALUES (1, 'foo, 'foo@example.com')") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .syntaxError)
    }

    @Test func `unknown keyword returns unrecognized`() {
        guard case let .failure(err) = Parser.parse("unknown") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .unrecognized)
    }

    @Test func `empty input returns unrecognized`() {
        guard case let .failure(err) = Parser.parse("") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .unrecognized)
    }

    @Test func `insert with negative id returns negativeId`() {
        guard case let .failure(err) = Parser.parse("INSERT INTO users VALUES (-1, 'foo', 'foo@example.com')") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .negativeId)
    }

    @Test func `insert with max length username and email succeeds`() {
        let username = String(repeating: "a", count: 32)
        let email = String(repeating: "b", count: 255)
        guard case let .success(stmt) = Parser.parse("INSERT INTO users VALUES (1, '\(username)', '\(email)')"),
              case let .insert(row) = stmt
        else {
            Issue.record("Expected .success(.insert(...))")
            return
        }
        #expect(row.username == username)
        #expect(row.email == email)
    }

    @Test func `insert with username too long returns stringTooLong`() {
        let username = String(repeating: "a", count: 33)
        guard case let .failure(err) = Parser.parse("INSERT INTO users VALUES (1, '\(username)', 'foo@example.com')") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .stringTooLong)
    }

    @Test func `insert with email too long returns stringTooLong`() {
        let email = String(repeating: "b", count: 256)
        guard case let .failure(err) = Parser.parse("INSERT INTO users VALUES (1, 'foo', '\(email)')") else {
            Issue.record("Expected .failure")
            return
        }
        #expect(err == .stringTooLong)
    }
}
