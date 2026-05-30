import Foundation

struct Account: Codable, Identifiable, Equatable {
    var id: Int
    var name: String
    var issuer: String
    var secret: String
    var tag: String
    var algorithm: String
    var digits: Int
    var period: Int
    var createdAt: Date
}

struct AccountStorage: Codable {
    var version: String
    var nextId: Int
    var accounts: [Account]

    static func empty() -> AccountStorage {
        AccountStorage(version: "1.0", nextId: 0, accounts: [])
    }
}
