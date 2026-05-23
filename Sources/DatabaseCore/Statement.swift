public enum PrepareError: Error {
    case syntaxError
    case unrecognized
}

public enum Statement {
    case insert(Row)
    case select

    public static func prepare(_ input: String) -> Result<Statement, PrepareError> {
        if input.hasPrefix("insert") {
            let parts = input.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let id = UInt32(parts[1]) else {
                return .failure(.syntaxError)
            }
            let row = Row(id: id, username: String(parts[2]), email: String(parts[3]))
            return .success(.insert(row))
        }
        if input == "select" { return .success(.select) }
        return .failure(.unrecognized)
    }

    public func execute(on table: Table) -> ExecuteResult {
        switch self {
        case let .insert(row):
            return table.insert(row: row)
        case .select:
            table.select().forEach { $0.printRow() }
            return .success
        }
    }
}
