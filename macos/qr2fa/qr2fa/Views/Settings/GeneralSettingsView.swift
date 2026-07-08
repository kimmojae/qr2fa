import SwiftUI

struct GeneralSettingsView: View {
    @Environment(StorageService.self) private var storageService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pathGroup
                actionsGroup
                Text("직접 고른 위치가 있으면 항상 우선하고, 없으면 iCloud Drive를 자동으로 사용합니다. iCloud Drive가 없는 Mac에서는 홈 폴더(~/.qr2fa)에 저장합니다.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 480, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var pathGroup: some View {
        HStack(alignment: .top) {
            Text("저장 위치")
                .font(.system(size: 12.5))
            Spacer(minLength: 12)
            Text(storageService.storagePath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color.settingsGroup)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private var actionsGroup: some View {
        HStack(spacing: 8) {
            Button("변경…") { changeLocation() }
            Button("Finder에서 보기") { revealInFinder() }
            Button("기본값으로 복원") { resetToDefault() }
                .disabled(storageService.isDefaultPath)
        }
        .buttonStyle(.bordered)
        .padding(12)
        .background(Color.settingsGroup)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    // MARK: - Actions

    private func changeLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "선택"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let newPath = url.appendingPathComponent("accounts.json").path
        do {
            try storageService.changePath(to: newPath)
        } catch {
            showError(error)
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: storageService.storagePath)])
    }

    private func resetToDefault() {
        do {
            try storageService.resetToDefaultPath()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "저장 위치를 변경할 수 없습니다"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private extension Color {
    static let settingsGroup = Color(nsColor: NSColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1))
}
