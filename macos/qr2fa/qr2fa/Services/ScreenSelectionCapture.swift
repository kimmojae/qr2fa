import Foundation
import ImageIO

/// Grabs one user-chosen piece of the screen by handing the job to macOS's own
/// screenshot UI (`screencapture -i`).
///
/// Letting the system drive the selection is what gets us the standard crosshair,
/// space-to-pick-a-window, Escape-to-cancel, and multi-monitor handling for free —
/// none of which we would get right by drawing our own overlay.
enum ScreenSelectionCapture {

    private static let tool = URL(fileURLWithPath: "/usr/sbin/screencapture")

    enum Outcome: Equatable {
        case captured
        case cancelled
        case failed
    }

    enum CaptureError: LocalizedError {
        case toolFailed
        case unreadableImage

        var errorDescription: String? {
            switch self {
            case .toolFailed: "화면을 캡처하지 못했습니다"
            case .unreadableImage: "캡처한 이미지를 읽지 못했습니다"
            }
        }
    }

    /// Returns the selected region, or `nil` when the user pressed Escape.
    static func selectRegion() async throws -> CGImage? {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("qr2fa-scan-\(UUID().uuidString).png")
        // The PNG holds a TOTP secret — it does not outlive this call.
        defer { try? FileManager.default.removeItem(at: destination) }

        let exitCode = try await run(writingTo: destination)
        let data = try? Data(contentsOf: destination)

        switch outcome(exitCode: exitCode, capturedBytes: data?.count) {
        case .cancelled:
            return nil
        case .failed:
            throw CaptureError.toolFailed
        case .captured:
            guard let data,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw CaptureError.unreadableImage
            }
            return image
        }
    }

    /// Escape and a genuine failure both exit non-zero, so the exit code alone cannot
    /// tell them apart — a cancelled selection is the one that writes no image.
    static func outcome(exitCode: Int32, capturedBytes: Int?) -> Outcome {
        guard let capturedBytes, capturedBytes > 0 else { return .cancelled }
        return exitCode == 0 ? .captured : .failed
    }

    private static func run(writingTo destination: URL) async throws -> Int32 {
        let process = Process()
        process.executableURL = tool
        // -i: the system crosshair (space switches to window selection).
        // -d: let macOS raise its own permission alert rather than us inventing one.
        process.arguments = ["-d", "-i", destination.path]

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
