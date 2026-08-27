import XCTest
@testable import qr2fa

final class ScreenSelectionCaptureTests: XCTestCase {

    /// Escape leaves no file behind — that, not the exit code, is what marks a cancel.
    func test_noFileMeansCancelled() {
        XCTAssertEqual(ScreenSelectionCapture.outcome(exitCode: 1, capturedBytes: nil), .cancelled)
    }

    func test_emptyFileMeansCancelled() {
        XCTAssertEqual(ScreenSelectionCapture.outcome(exitCode: 1, capturedBytes: 0), .cancelled)
    }

    /// A clean exit with nothing written is a cancel too, not a success with no image.
    func test_cleanExitWithNoFileIsStillCancelled() {
        XCTAssertEqual(ScreenSelectionCapture.outcome(exitCode: 0, capturedBytes: nil), .cancelled)
    }

    func test_cleanExitWithAnImageIsCaptured() {
        XCTAssertEqual(ScreenSelectionCapture.outcome(exitCode: 0, capturedBytes: 8_192), .captured)
    }

    /// A written-but-failed run is a real failure, not a silent cancel.
    func test_failedExitWithAnImageIsFailure() {
        XCTAssertEqual(ScreenSelectionCapture.outcome(exitCode: 1, capturedBytes: 8_192), .failed)
    }
}
