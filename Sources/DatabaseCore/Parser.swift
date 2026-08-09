public enum Statement {
    case insert(Row)
    case select
}

public enum ParseError: Error {
    case syntaxError
    case unrecognized
    case negativeId
    case stringTooLong
}

/// A minimal SQL parser supporting the single hardcoded `users` table:
///   INSERT INTO users VALUES (<id>, '<username>', '<email>')
///   SELECT * FROM users
/// Keywords and the table name are case-insensitive; string literals use single quotes.
public enum Parser {
    private static let tableName = "users"

    private enum Token: Equatable {
        case word(String)
        case int(Int)
        case string(String)
        case lparen
        case rparen
        case comma
        case star
    }

    public static func parse(_ input: String) -> Result<Statement, ParseError> {
        guard let tokens = tokenize(input) else {
            return .failure(.syntaxError)
        }
        guard case let .word(keyword)? = tokens.first else {
            return .failure(.unrecognized)
        }
        switch keyword.lowercased() {
        case "insert":
            return parseInsert(tokens)
        case "select":
            return parseSelect(tokens)
        default:
            return .failure(.unrecognized)
        }
    }

    /// INSERT INTO users VALUES ( int , string , string )
    private static func parseInsert(_ tokens: [Token]) -> Result<Statement, ParseError> {
        guard tokens.count == 11,
              case let .word(into) = tokens[1], into.lowercased() == "into",
              case let .word(table) = tokens[2], table.lowercased() == tableName,
              case let .word(values) = tokens[3], values.lowercased() == "values",
              tokens[4] == .lparen,
              case let .int(idInt) = tokens[5],
              tokens[6] == .comma,
              case let .string(username) = tokens[7],
              tokens[8] == .comma,
              case let .string(email) = tokens[9],
              tokens[10] == .rparen
        else {
            return .failure(.syntaxError)
        }
        guard idInt >= 0 else { return .failure(.negativeId) }
        guard idInt <= UInt32.max else { return .failure(.syntaxError) }
        guard username.count <= 32 else { return .failure(.stringTooLong) }
        guard email.count <= 255 else { return .failure(.stringTooLong) }
        let row = Row(id: UInt32(idInt), username: username, email: email)
        return .success(.insert(row))
    }

    /// SELECT * FROM users
    private static func parseSelect(_ tokens: [Token]) -> Result<Statement, ParseError> {
        guard tokens.count == 4,
              tokens[1] == .star,
              case let .word(from) = tokens[2], from.lowercased() == "from",
              case let .word(table) = tokens[3], table.lowercased() == tableName
        else {
            return .failure(.syntaxError)
        }
        return .success(.select)
    }

    /// Splits the input into tokens. Returns nil on any lexical error
    /// (an unterminated string literal or an unexpected character).
    private static func tokenize(_ input: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case " ", "\t", "\n", "\r":
                i += 1
            case "(":
                tokens.append(.lparen)
                i += 1
            case ")":
                tokens.append(.rparen)
                i += 1
            case ",":
                tokens.append(.comma)
                i += 1
            case "*":
                tokens.append(.star)
                i += 1
            case "'":
                i += 1
                var value = ""
                while i < chars.count, chars[i] != "'" {
                    value.append(chars[i])
                    i += 1
                }
                guard i < chars.count else { return nil } // unterminated string
                i += 1 // consume closing quote
                tokens.append(.string(value))
            case "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
                var text = String(c)
                i += 1
                while i < chars.count, chars[i].isNumber {
                    text.append(chars[i])
                    i += 1
                }
                guard let value = Int(text) else { return nil }
                tokens.append(.int(value))
            case _ where c.isLetter:
                var text = String(c)
                i += 1
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" {
                    text.append(chars[i])
                    i += 1
                }
                tokens.append(.word(text))
            default:
                return nil // unexpected character
            }
        }
        return tokens
    }
}
