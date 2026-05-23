import Foundation

public struct Row: Equatable {
    private static let idSize = 4
    private static let usernameSize = 32
    private static let emailSize = 255
    static let size = idSize + usernameSize + emailSize // 291

    private static let idOffset = 0
    private static let usernameOffset = idSize
    private static let emailOffset = idSize + usernameSize

    public let id: UInt32
    public let username: String
    public let email: String

    public init(id: UInt32, username: String, email: String) {
        self.id = id
        self.username = username
        self.email = email
    }

    func serialize() -> Data {
        var data = Data(count: Row.size)
        var idVal = id.littleEndian
        withUnsafeBytes(of: &idVal) {
            data.replaceSubrange(Row.idOffset ..< Row.idOffset + Row.idSize, with: $0)
        }
        let usernameBytes = Array(username.utf8.prefix(Row.usernameSize))
        data.replaceSubrange(Row.usernameOffset ..< Row.usernameOffset + usernameBytes.count, with: usernameBytes)
        let emailBytes = Array(email.utf8.prefix(Row.emailSize))
        data.replaceSubrange(Row.emailOffset ..< Row.emailOffset + emailBytes.count, with: emailBytes)
        return data
    }

    static func deserialize(from data: Data) -> Row {
        let idBytes = data[Row.idOffset ..< Row.idOffset + Row.idSize]
        let id = idBytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let usernameData = data[Row.usernameOffset ..< Row.usernameOffset + Row.usernameSize]
        let username = String(bytes: usernameData.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        let emailData = data[Row.emailOffset ..< Row.emailOffset + Row.emailSize]
        let email = String(bytes: emailData.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        return Row(id: id, username: username, email: email)
    }

    func printRow() {
        print("(\(id), \(username), \(email))")
    }
}
