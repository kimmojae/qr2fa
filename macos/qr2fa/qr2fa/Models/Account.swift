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
        let encodedIssuer = issuer.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? issuer
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let label = issuer.isEmpty ? encodedName : "\(encodedIssuer):\(encodedName)"
        let encodedSecret = secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? secret
        let encodedAlgorithm = algorithm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? algorithm
        var items = [
            "secret=\(encodedSecret)",
            "digits=\(digits)",
            "period=\(period)",
            "algorithm=\(encodedAlgorithm)"
        ]
        if !issuer.isEmpty {
            let encodedIssuerQuery = issuer.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? issuer
            items.append("issuer=\(encodedIssuerQuery)")
        }
        return "otpauth://totp/\(label)?\(items.joined(separator: "&"))"
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
