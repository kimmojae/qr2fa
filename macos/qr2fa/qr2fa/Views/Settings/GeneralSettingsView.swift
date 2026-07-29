import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(StorageService.self) private var storageService
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showingLocationInfo = false

    var body: some View {
        Form {
            Section {
                Toggle("로그인 시 시작", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { _, newValue in
                        setStartAtLogin(newValue)
                    }
            }

            Section {
                LabeledContent {
                    Text(storageService.storagePath)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } label: {
                    HStack(spacing: 4) {
                        Text("저장 위치")
                        Button {
                            showingLocationInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .popover(isPresented: $showingLocationInfo) {
                            Text("MFA 데이터가 저장되는 폴더입니다. iCloud Drive를 고르면 다른 Mac과 자동으로 동기화됩니다. 이 설정은 Mac마다 따로 적용됩니다.")
                                .frame(width: 260)
                                .padding()
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button("변경…") { changeLocation() }
                    Button("Finder에서 보기") { revealInFinder() }
                    Button("기본값으로 복원") { resetToDefault() }
                        .disabled(storageService.isDefaultPath)
                }
            }

            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appName)
                            .font(.system(size: 30, weight: .semibold))
                        Text("Version \(appVersion)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Copyright © 2026 kimmojae")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Link("GitHub", destination: URL(string: "https://github.com/kimmojae/qr2fa")!)
                            .font(.system(size: 12))
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - App info

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Qr2fa"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    // MARK: - Actions

    private func setStartAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            startAtLogin = !enabled
            showError(error, title: "로그인 항목 설정을 변경할 수 없습니다")
        }
    }

    private func changeLocation() {
        // 이 앱은 LSUIElement(액세서리) 앱이라, 혹시 전면이 아니게 된 상태에서
        // 패널을 열면 뒤로 밀릴 수 있어 먼저 활성화해 둔다.
        NSApp.activate(ignoringOtherApps: true)
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

    private func showError(_ error: Error, title: String = "저장 위치를 변경할 수 없습니다") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
