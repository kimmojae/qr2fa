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
    /// 자유 메모. 계정 이름만으로는 구분이 안 될 때 쓰라고 둔 자리다.
    var memo: String = ""
}

extension Account {
    /// 디코딩을 직접 쓰는 이유는 `memo` 때문이다.
    ///
    /// Swift의 자동 `Decodable`은 **키가 없으면 프로퍼티 기본값을 쓰지 않고 실패한다.**
    /// `memo`가 생기기 전에 저장된 파일에는 그 키가 없으므로, 자동 구현에 맡기면 기존
    /// 계정이 통째로 안 읽힌다(복구 불가능한 시크릿이 담긴 파일이다).
    ///
    /// `init(from:)`을 타입 본문이 아니라 **확장에** 두는 것도 의도다 — 본문에 두면
    /// 멤버와이즈 이니셜라이저가 사라져서 계정을 만드는 모든 자리가 깨진다.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        issuer = try container.decode(String.self, forKey: .issuer)
        secret = try container.decode(String.self, forKey: .secret)
        tag = try container.decode(String.self, forKey: .tag)
        algorithm = try container.decode(String.self, forKey: .algorithm)
        digits = try container.decode(Int.self, forKey: .digits)
        period = try container.decode(Int.self, forKey: .period)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        memo = try container.decodeIfPresent(String.self, forKey: .memo) ?? ""
    }
}

extension Account {
    /// How this account is grouped and titled in the UI. An account with no issuer
    /// stands as its own service, so it is labelled by its name.
    var displayIssuer: String { issuer.isEmpty ? name : issuer }

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
