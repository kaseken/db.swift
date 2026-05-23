@testable import DatabaseCore
import Foundation
import Testing

struct RowTests {
    @Test func `serialize produces correct byte layout`() {
        let row = Row(id: 1, username: "foo", email: "foo@example.com")
        let data = row.serialize()

        #expect(data.count == Row.size)

        // id: little-endian UInt32 at offset 0
        let id = data[0 ..< 4].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        #expect(id == 1)

        // username at offset 4, zero-padded to 32 bytes
        let username = String(bytes: data[4 ..< 36].prefix { $0 != 0 }, encoding: .utf8)
        #expect(username == "foo")
        #expect(data[7] == 0) // byte after "foo" (3 bytes) is zero

        // email at offset 36, zero-padded to 255 bytes
        let email = String(bytes: data[36 ..< 291].prefix { $0 != 0 }, encoding: .utf8)
        #expect(email == "foo@example.com")
        #expect(data[51] == 0) // byte after "foo@example.com" (15 bytes) is zero
    }

    @Test func `deserialize reconstructs the original row`() {
        let original = Row(id: 42, username: "bob", email: "bob@example.com")
        let recovered = Row.deserialize(from: original.serialize())
        #expect(recovered == original)
    }

    @Test func `max length username round-trips correctly`() {
        let username = String(repeating: "a", count: 32)
        let row = Row(id: 1, username: username, email: "e@example.com")
        let recovered = Row.deserialize(from: row.serialize())
        #expect(recovered.username == username)
    }

    @Test func `max length email round-trips correctly`() {
        let email = String(repeating: "x", count: 255)
        let row = Row(id: 1, username: "u", email: email)
        let recovered = Row.deserialize(from: row.serialize())
        #expect(recovered.email == email)
    }
}
