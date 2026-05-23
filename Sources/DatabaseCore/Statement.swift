public enum Statement: Equatable {
    case insert // Part 3で case insert(Row) に変える
    case select

    public init?(_ input: String) {
        if input.hasPrefix("insert") { self = .insert; return }
        if input == "select" { self = .select; return }
        return nil
    }

    public func execute() {
        switch self {
        case .insert:
            print("This is where we would do an insert.")
        case .select:
            print("This is where we would do a select.")
        }
    }
}
