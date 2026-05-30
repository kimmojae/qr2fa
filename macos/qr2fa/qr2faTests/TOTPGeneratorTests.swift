import XCTest
@testable import qr2fa

final class TOTPGeneratorTests: XCTestCase {

    // RFC 6238 Appendix B test vectors.
    // Seed: "12345678901234567890" (20 bytes)
    // Base32: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    // T=59 → time step=1 → 8-digit SHA1: 94287082 → 6-digit: 287082

    func test_rfc6238_sha1_6digit() throws {
        let code = try TOTPGenerator.generate(
            secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            date: Date(timeIntervalSince1970: 59),
            digits: 6, period: 30, algorithm: .sha1
        )
        XCTAssertEqual(code, "287082")
    }

    func test_rfc6238_sha1_8digit() throws {
        let code = try TOTPGenerator.generate(
            secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            date: Date(timeIntervalSince1970: 59),
            digits: 8, period: 30, algorithm: .sha1
        )
        XCTAssertEqual(code, "94287082")
    }

    func test_code_is_numeric_and_correct_length() throws {
        let code = try TOTPGenerator.generate(
            secret: "JBSWY3DPEHPK3PXP",
            date: Date(timeIntervalSince1970: 1000),
            digits: 6, period: 30, algorithm: .sha1
        )
        XCTAssertEqual(code.count, 6)
        XCTAssertTrue(code.allSatisfy(\.isNumber))
    }

    func test_remainingSeconds() {
        // 35 seconds into 30s period: elapsed=5, remaining=25
        XCTAssertEqual(TOTPGenerator.remainingSeconds(date: Date(timeIntervalSince1970: 35), period: 30), 25)
        // Exactly on boundary: elapsed=0, remaining=30
        XCTAssertEqual(TOTPGenerator.remainingSeconds(date: Date(timeIntervalSince1970: 30), period: 30), 30)
    }

    func test_invalidSecret_throws() {
        XCTAssertThrowsError(try TOTPGenerator.generate(
            secret: "!!!INVALID!!!",
            date: Date(timeIntervalSince1970: 0),
            digits: 6, period: 30, algorithm: .sha1
        ))
    }

    func test_secretWithPadding_sameAsWithout() throws {
        let code1 = try TOTPGenerator.generate(
            secret: "JBSWY3DPEHPK3PXP",
            date: Date(timeIntervalSince1970: 59),
            digits: 6, period: 30, algorithm: .sha1
        )
        let code2 = try TOTPGenerator.generate(
            secret: "JBSWY3DPEHPK3PXP====",
            date: Date(timeIntervalSince1970: 59),
            digits: 6, period: 30, algorithm: .sha1
        )
        XCTAssertEqual(code1, code2)
    }

    func test_formattedCode_6digits() {
        XCTAssertEqual(TOTPGenerator.formattedCode("123456"), "123 456")
    }

    func test_formattedCode_8digits() {
        XCTAssertEqual(TOTPGenerator.formattedCode("12345678"), "1234 5678")
    }
}
