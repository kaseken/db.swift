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

public enum Parser {
    public static func parse(_ input: String) -> Result<Statement, ParseError> {
        if input.hasPrefix("insert") {
            let parts = input.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let idInt = Int(parts[1]) else {
                return .failure(.syntaxError)
            }
            guard idInt >= 0 else { return .failure(.negativeId) }
            let username = String(parts[2])
            let email = String(parts[3])
            guard username.count <= 32 else { return .failure(.stringTooLong) }
            guard email.count <= 255 else { return .failure(.stringTooLong) }
            let row = Row(id: UInt32(idInt), username: username, email: email)
            return .success(.insert(row))
        }
        if input == "select" {
            return .success(.select)
        }
        return .failure(.unrecognized)
    }
}
