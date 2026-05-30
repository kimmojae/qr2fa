import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @Environment(StorageService.self) private var storageService
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(storageService.storagePath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Finder에서 보기") {
                        NSWorkspace.shared.selectFile(
                            storageService.storagePath,
                            inFileViewerRootedAtPath: ""
                        )
                    }
                    Button("변경") { changeStoragePath() }
                }
            } header: {
                Text("저장 경로")
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func changeStoragePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "선택"
        panel.message = "accounts.json을 저장할 폴더를 선택하세요"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let newPath = url.appendingPathComponent("accounts.json").path

        do {
            try storageService.changePath(to: newPath)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
