import Foundation

struct MigrationParser {

    static func parse(url: String) -> [Account]? {
        guard url.hasPrefix("otpauth-migration://"),
              let comps = URLComponents(string: url),
              var dataStr = comps.queryItems?.first(where: { $0.name == "data" })?.value
        else { return nil }

        dataStr = dataStr
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = dataStr.count % 4
        if rem != 0 { dataStr += String(repeating: "=", count: 4 - rem) }

        guard let data = Data(base64Encoded: dataStr) else { return nil }
        return parsePayload(data)
    }

    // MARK: - Protobuf parsing

    private static func parsePayload(_ data: Data) -> [Account] {
        var accounts: [Account] = []
        var offset = 0
        while offset < data.count {
            guard let (fieldNum, wireType, next) = readTag(data, at: offset) else { break }
            offset = next
            if fieldNum == 1, wireType == 2 {
                guard let (len, afterLen) = readVarint(data, at: offset) else { break }
                offset = afterLen
                let end = min(offset + Int(len), data.count)
                if let acc = parseOtpParameters(Data(data[offset..<end])) {
                    accounts.append(acc)
                }
                offset += Int(len)
            } else {
                guard let newOff = skipField(data, at: offset, wireType: wireType) else { break }
                offset = newOff
            }
        }
        return accounts
    }

    private static func parseOtpParameters(_ data: Data) -> Account? {
        var secretBytes: Data?
        var name = ""
        var issuer = ""
        var algorithm = "SHA1"
        var digits = 6
        var offset = 0

        while offset < data.count {
            guard let (fieldNum, wireType, next) = readTag(data, at: offset) else { break }
            offset = next
            switch (fieldNum, wireType) {
            case (1, 2):
                guard let (len, afterLen) = readVarint(data, at: offset) else { return nil }
                offset = afterLen
                secretBytes = Data(data[offset..<min(offset + Int(len), data.count)])
                offset += Int(len)
            case (2, 2):
                guard let (len, afterLen) = readVarint(data, at: offset) else { return nil }
                offset = afterLen
                name = String(data: Data(data[offset..<min(offset + Int(len), data.count)]), encoding: .utf8) ?? ""
                offset += Int(len)
            case (3, 2):
                guard let (len, afterLen) = readVarint(data, at: offset) else { return nil }
                offset = afterLen
                issuer = String(data: Data(data[offset..<min(offset + Int(len), data.count)]), encoding: .utf8) ?? ""
                offset += Int(len)
            case (4, 0):
                guard let (val, afterVal) = readVarint(data, at: offset) else { return nil }
                offset = afterVal
                algorithm = val == 2 ? "SHA256" : val == 3 ? "SHA512" : "SHA1"
            case (5, 0):
                guard let (val, afterVal) = readVarint(data, at: offset) else { return nil }
                offset = afterVal
                digits = val == 2 ? 8 : 6
            default:
                guard let newOff = skipField(data, at: offset, wireType: wireType) else { return nil }
                offset = newOff
            }
        }

        guard let secretBytes else { return nil }
        let secret = base32Encode(secretBytes)

        var accountName = name
        if issuer.isEmpty, name.contains(":") {
            let parts = name.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                issuer = String(parts[0])
                accountName = String(parts[1])
            }
        }

        return Account(
            id: 0, name: accountName, issuer: issuer,
            secret: secret, tag: "",
            algorithm: algorithm, digits: digits, period: 30,
            createdAt: Date()
        )
    }

    // MARK: - Wire helpers

    private static func readTag(_ data: Data, at offset: Int) -> (Int, Int, Int)? {
        guard let (value, next) = readVarint(data, at: offset) else { return nil }
        return (value >> 3, value & 0x7, next)
    }

    private static func readVarint(_ data: Data, at offset: Int) -> (Int, Int)? {
        var result = 0
        var shift = 0
        var idx = offset
        while idx < data.count {
            let byte = Int(data[idx]); idx += 1
            result |= (byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (result, idx) }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    private static func skipField(_ data: Data, at offset: Int, wireType: Int) -> Int? {
        switch wireType {
        case 0:
            guard let (_, next) = readVarint(data, at: offset) else { return nil }
            return next
        case 1: return offset + 8
        case 2:
            guard let (len, afterLen) = readVarint(data, at: offset) else { return nil }
            return afterLen + Int(len)
        case 5: return offset + 4
        default: return nil
        }
    }

    private static func base32Encode(_ data: Data) -> String {
        let alpha = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var result = ""
        var buf = 0, bitsLeft = 0
        for byte in data {
            buf = (buf << 8) | Int(byte)
            bitsLeft += 8
            while bitsLeft >= 5 {
                bitsLeft -= 5
                result.append(alpha[(buf >> bitsLeft) & 0x1F])
            }
        }
        if bitsLeft > 0 { result.append(alpha[(buf << (5 - bitsLeft)) & 0x1F]) }
        return result
    }
}
