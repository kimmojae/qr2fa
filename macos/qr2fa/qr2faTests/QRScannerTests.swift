import XCTest
import CoreImage
@testable import qr2fa

final class QRScannerTests: XCTestCase {

    // MARK: - Helpers

    /// Renders `payload` as a QR code big enough for Vision to read reliably.
    private func qrCIImage(_ payload: String) throws -> CIImage {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        return try XCTUnwrap(filter.outputImage)
            .transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    }

    private func qrImage(_ payload: String) throws -> CGImage {
        let ci = try qrCIImage(payload)
        return try XCTUnwrap(CIContext().createCGImage(ci, from: ci.extent))
    }

    /// One image holding two QR codes side by side — what a sloppy selection looks like.
    private func qrImages(_ left: String, _ right: String) throws -> CGImage {
        let a = try qrCIImage(left)
        let b = try qrCIImage(right).transformed(
            by: CGAffineTransform(translationX: a.extent.width + 40, y: 0)
        )
        let combined = b.composited(over: a)
        return try XCTUnwrap(CIContext().createCGImage(combined, from: combined.extent))
    }

    // MARK: - Tests

    func test_readsTheAccountInTheSelectedRegion() async throws {
        let payload = "otpauth://totp/GitHub:mojaekim@gmail.com?secret=AAAAAAAAAAAAAAAA"

        let urls = try await QRScanner.otpauthURLs(in: try qrImage(payload))

        XCTAssertEqual(urls, [payload])
    }

    /// Drives the "select just one" message — the view has to know there was more than one.
    func test_reportsEveryQRCodeInTheRegion() async throws {
        let image = try qrImages(
            "otpauth://totp/First:a@example.com?secret=AAAAAAAAAAAAAAAA",
            "otpauth://totp/Second:b@example.com?secret=BBBBBBBBBBBBBBBB"
        )

        let urls = try await QRScanner.otpauthURLs(in: image)

        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(urls.contains { $0.contains("First") })
        XCTAssertTrue(urls.contains { $0.contains("Second") })
    }

    func test_keepsMigrationPayloads() async throws {
        let payload = "otpauth-migration://offline?data=CjEKCkhlbGxvIXjerw"

        let urls = try await QRScanner.otpauthURLs(in: try qrImage(payload))

        XCTAssertEqual(urls, [payload])
    }

    func test_ignoresUnrelatedQRCodes() async throws {
        let urls = try await QRScanner.otpauthURLs(in: try qrImage("https://example.com"))

        XCTAssertTrue(urls.isEmpty)
    }

    func test_returnsNothingForABlankRegion() async throws {
        let blank = CGContext(
            data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        blank.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        blank.fill(CGRect(x: 0, y: 0, width: 200, height: 200))

        let urls = try await QRScanner.otpauthURLs(in: try XCTUnwrap(blank.makeImage()))

        XCTAssertTrue(urls.isEmpty)
    }
}
