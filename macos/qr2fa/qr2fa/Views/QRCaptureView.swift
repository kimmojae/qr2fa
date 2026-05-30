import SwiftUI

struct QRCaptureView: View {
    let onCapture: (String) -> Void
    @Environment(StorageService.self) private var storageService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("QR 코드 스캔")
                .font(.headline)
            Text("(Task 12에서 구현 예정)")
                .foregroundStyle(.secondary)
            Button("닫기") { dismiss() }
        }
        .frame(width: 320, height: 200)
        .padding()
    }
}
