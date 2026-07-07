import SwiftUI

struct GeneralSettingsView: View {
    @Environment(StorageService.self) private var storageService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("저장 위치")
                storageCard
                priorityList
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.settingsAccent)
                    .frame(width: 30, height: 30)
                    .background(Color.settingsAccent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.settingsAccent)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.settingsAccent)
                    }
                    Text(storageService.storagePath)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            HStack(spacing: 8) {
                Button("변경…") { changeLocation() }
                    .buttonStyle(.borderedProminent)
                Button("Finder에서 보기") { revealInFinder() }
                    .buttonStyle(.bordered)
                Button("기본값으로 복원") { resetToDefault() }
                    .buttonStyle(.bordered)
                    .disabled(storageService.isDefaultPath)
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(Color.settingsCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var priorityList: some View {
        VStack(alignment: .leading, spacing: 10) {
            priorityRow(
                1, title: "사용자 지정 위치",
                detail: "\"변경…\"으로 직접 고른 폴더가 있으면 항상 우선합니다.",
                isCurrent: storageService.locationKind == .custom
            )
            priorityRow(
                2, title: "iCloud Drive",
                detail: "iCloud Drive를 쓰는 Mac이면 자동으로 여기에 저장해 다른 기기와 동기화합니다.",
                isCurrent: storageService.locationKind == .iCloud
            )
            priorityRow(
                3, title: "로컬 폴더 (~/.qr2fa)",
                detail: "iCloud Drive가 없는 Mac에서는 홈 폴더 아래에 저장합니다.",
                isCurrent: storageService.locationKind == .local
            )
        }
        .padding(.top, 6)
    }

    private func priorityRow(_ number: Int, title: String, detail: String, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isCurrent ? .white : .secondary)
                .frame(width: 20, height: 20)
                .background(isCurrent ? Color.settingsAccent : Color.settingsCard)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.settingsAccent : .primary)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusIcon: String {
        switch storageService.locationKind {
        case .custom: return "folder"
        case .iCloud: return "icloud"
        case .local: return "internaldrive"
        }
    }

    private var statusText: String {
        switch storageService.locationKind {
        case .custom: return "사용자 지정 위치에 저장 중"
        case .iCloud: return "iCloud Drive에 저장 중"
        case .local: return "로컬 폴더에 저장 중"
        }
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }
}

private extension Color {
    static let settingsCard = Color(nsColor: NSColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1))
    static let settingsAccent = Color(nsColor: .systemGreen)
}
