import CoreGraphics
import Vision

/// Reads TOTP payloads out of a captured screen region.
///
/// Kept separate from the capture step so that "what did the user select" and
/// "what did we find in it" can be reasoned about — and tested — independently.
enum QRScanner {

    /// Payload shapes the account editor knows how to consume.
    private static let acceptedPrefixes = ["otpauth://totp/", "otpauth-migration://"]

    /// Every usable payload in `image`. More than one means the selection was too
    /// wide — the caller asks the user to narrow it rather than guessing.
    static func otpauthURLs(in image: CGImage) async throws -> [String] {
        try await payloads(in: image).filter { payload in
            acceptedPrefixes.contains(where: payload.hasPrefix)
        }
    }

    private static func payloads(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { req, err in
                if let err {
                    continuation.resume(throwing: err)
                    return
                }
                let values = (req.results as? [VNBarcodeObservation] ?? [])
                    .compactMap { $0.payloadStringValue }
                continuation.resume(returning: values)
            }
            request.symbologies = [.qr]

            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
