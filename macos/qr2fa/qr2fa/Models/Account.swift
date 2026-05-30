import Foundation

struct Account: Codable, Identifiable, Equatable, Hashable {
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

extension Account {
    func toOTPAuthURL() -> String {
        let label = issuer.isEmpty ? name : "\(issuer):\(name)"
        let encoded = label.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? label
        var items = [
            "secret=\(secret)",
            "digits=\(digits)",
            "period=\(period)",
            "algorithm=\(algorithm)"
        ]
        if !issuer.isEmpty {
            let encodedIssuer = issuer.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? issuer
            items.insert("issuer=\(encodedIssuer)", at: 0)
        }
        return "otpauth://totp/\(encoded)?\(items.joined(separator: "&"))"
    }
}

struct AccountStorage: Codable {
    var version: String
    var nextId: Int
    var accounts: [Account]

    static func empty() -> AccountStorage {
        AccountStorage(version: "1.0", nextId: 0, accounts: [])
    }
}
