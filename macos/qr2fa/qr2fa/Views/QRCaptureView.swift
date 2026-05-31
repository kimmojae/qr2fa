import SwiftUI
import ScreenCaptureKit
import Vision
import AppKit

struct QRCaptureView: View {
    let onCapture: (String) -> Void
    @Environment(StorageService.self) private var storageService
    @Environment(\.dismiss) private var dismiss

    @State private var status: CaptureStatus = .idle

    enum CaptureStatus {
        case idle
        case capturing
        case multipleFound([String])
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("QR 코드 스캔")
                .font(.headline)

            switch status {
            case .idle:
                VStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("화면에 QR 코드를 표시한 뒤\n아래 버튼을 누르세요")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("화면 스캔") {
                        Task { await capture() }
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .capturing:
                ProgressView("스캔 중...")

            case .multipleFound(let urls):
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 36))
                    Text("\(urls.count)개 QR 코드 발견 — 선택하세요")
                    ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                        Button(urlDisplayLabel(url)) {
                            onCapture(url)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }

            case .failed(let message):
                VStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 36))
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("다시 시도") { status = .idle }
                        .buttonStyle(.bordered)
                }
            }

            Spacer()
            Button("취소") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding()
        .frame(width: 320, height: 300)
    }

    // MARK: - Capture flow

    private func capture() async {
        status = .capturing
        do {
            let cgImage = try await captureScreen()
            let urls = try await detectQRCodes(in: cgImage)
                .filter { $0.hasPrefix("otpauth://totp/") || $0.hasPrefix("otpauth-migration://") }

            await MainActor.run {
                if urls.isEmpty {
                    status = .failed("QR 코드를 찾을 수 없습니다.\n화면에 QR 코드가 보이는지 확인하세요.")
                } else if urls.count == 1 {
                    onCapture(urls[0])
                    dismiss()
                } else {
                    status = .multipleFound(urls)
                }
            }
        } catch {
            await MainActor.run {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func captureScreen() async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw QRCaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width * 2
        config.height = display.height * 2
        config.scalesToFit = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    private func detectQRCodes(in cgImage: CGImage) async throws -> [String] {
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

            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func urlDisplayLabel(_ urlString: String) -> String {
        guard let components = URLComponents(string: urlString) else { return urlString }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.removingPercentEncoding ?? path
    }
}

enum QRCaptureError: LocalizedError {
    case noDisplay
    var errorDescription: String? { "화면을 찾을 수 없습니다" }
}
