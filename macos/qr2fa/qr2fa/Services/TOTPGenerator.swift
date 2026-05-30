import CryptoKit
import Foundation

struct TOTPGenerator {

    enum Algorithm {
        case sha1, sha256, sha512

        static func from(_ string: String) -> Algorithm {
            switch string.uppercased() {
            case "SHA256": return .sha256
            case "SHA512": return .sha512
            default:       return .sha1
            }
        }
    }

    static func generate(
        secret: String,
        date: Date = .init(),
        digits: Int = 6,
        period: Int = 30,
        algorithm: Algorithm = .sha1
    ) throws -> String {
        let stripped = secret.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        guard let secretData = base32Decode(stripped) else {
            throw TOTPError.invalidSecret
        }

        let timeStep = UInt64(date.timeIntervalSince1970) / UInt64(period)
        var counter = timeStep.bigEndian
        let counterData = Data(bytes: &counter, count: 8)
        let key = SymmetricKey(data: secretData)

        let hmacData: Data
        switch algorithm {
        case .sha1:
            hmacData = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key))
        case .sha256:
            hmacData = Data(HMAC<SHA256>.authenticationCode(for: counterData, using: key))
        case .sha512:
            hmacData = Data(HMAC<SHA512>.authenticationCode(for: counterData, using: key))
        }

        let offset = Int(hmacData[hmacData.count - 1] & 0x0f)
        let truncated = (UInt32(hmacData[offset]     & 0x7f) << 24)
                      | (UInt32(hmacData[offset + 1])        << 16)
                      | (UInt32(hmacData[offset + 2])        <<  8)
                      |  UInt32(hmacData[offset + 3])

        let otp = truncated % UInt32(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)d", otp)
    }

    static func generate(account: Account, date: Date = .init()) throws -> String {
        try generate(
            secret: account.secret,
            date: date,
            digits: account.digits,
            period: account.period,
            algorithm: Algorithm.from(account.algorithm)
        )
    }

    static func remainingSeconds(date: Date = .init(), period: Int = 30) -> Int {
        let elapsed = Int(date.timeIntervalSince1970) % period
        return period - elapsed
    }

    static func formattedCode(_ code: String) -> String {
        switch code.count {
        case 6: return "\(code.prefix(3)) \(code.suffix(3))"
        case 8: return "\(code.prefix(4)) \(code.suffix(4))"
        default: return code
        }
    }

    // MARK: - Private

    private static func base32Decode(_ input: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = 0
        var value = 0
        var output = Data()

        for char in input {
            guard let idx = alphabet.firstIndex(of: char) else { return nil }
            let pos = alphabet.distance(from: alphabet.startIndex, to: idx)
            value = (value << 5) | pos
            bits += 5
            if bits >= 8 {
                output.append(UInt8(truncatingIfNeeded: value >> (bits - 8)))
                bits -= 8
            }
        }
        return output.isEmpty ? nil : output
    }
}

enum TOTPError: Error {
    case invalidSecret
}
