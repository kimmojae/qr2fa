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
                    // "기본값으로 복원"이라고 쓰면 설정만 초기화되는 것처럼 읽히지만,
                    // 실제로는 저장 폴더가 옮겨가고 계정 파일이 따라간다. 라벨을 동작에 맞춘다.
                    Button("기본 폴더로 되돌리기") { resetToDefault() }
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
        moveStorage(to: url.path)
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: storageService.storagePath)])
    }

    private func resetToDefault() {
        moveStorage(to: storageService.defaultDirectory)
    }

    /// 저장 폴더를 옮기는 단일 통로. "변경…"과 "기본 폴더로 되돌리기"가 같은 확인 절차를 탄다.
    ///
    /// 대상 폴더에 이미 계정 파일이 있으면 조용히 덮어쓰지 않는다 — 어느 쪽을 정본으로 삼을지
    /// 반드시 사용자에게 묻는다. 여러 Mac에서 각자 계정을 등록한 뒤 iCloud로 합치는 건
    /// 정상 사용 패턴이고, 그 순간 잘못 고르면 복구 불가능한 MFA 시크릿이 날아간다.
    private func moveStorage(to directory: String) {
        let target = "\(directory)/accounts.json"
        guard target != storageService.storagePath else { return }

        let strategy: StorageService.PathChangeStrategy
        switch StorageService.inspectTarget(directory: directory) {
        case .absent:
            // 대상이 비어 있으면 지금 계정을 그대로 데려간다. 잃을 게 없으니 묻지 않는다.
            strategy = .copyCurrent

        case .accounts(let count):
            guard let choice = askWhichFileWins(directory: directory, targetCount: count) else { return }
            strategy = choice

        case .unreadable:
            let alert = NSAlert()
            alert.messageText = "선택한 폴더에 읽을 수 없는 accounts.json이 있습니다"
            alert.informativeText = """
                \(abbreviate(target))

                계속하면 그 파일을 accounts.json.bak-<시각>으로 백업한 뒤 현재 계정 \
                \(storageService.accounts.count)개로 새로 씁니다.
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "백업 후 계속")
            alert.addButton(withTitle: "취소")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            strategy = .copyCurrent
        }

        do {
            let backup = try storageService.changePath(to: target, strategy: strategy)
            if let backup {
                let done = NSAlert()
                done.messageText = "저장 위치를 바꿨습니다"
                done.informativeText = "기존 파일은 다음 이름으로 백업했습니다:\n\(abbreviate(backup))"
                done.runModal()
            }
        } catch {
            showError(error)
        }
    }

    /// 대상에 계정 파일이 있을 때 어느 쪽을 정본으로 삼을지 묻는다. 취소면 nil.
    private func askWhichFileWins(
        directory: String,
        targetCount: Int
    ) -> StorageService.PathChangeStrategy? {
        let alert = NSAlert()
        alert.messageText = "선택한 폴더에 이미 계정 파일이 있습니다"
        alert.informativeText = """
            \(abbreviate(directory))/accounts.json — 계정 \(targetCount)개
            현재 위치 — 계정 \(storageService.accounts.count)개

            어느 쪽을 계속 쓸지 고르세요. 덮어쓰기를 고르면 그 폴더의 기존 파일은 \
            accounts.json.bak-<시각>으로 백업합니다.
            """
        alert.alertStyle = .warning
        // 기본 버튼은 아무것도 덮지 않는 쪽으로 둔다.
        alert.addButton(withTitle: "그 폴더의 파일 사용")
        alert.addButton(withTitle: "현재 계정으로 덮어쓰기")
        alert.addButton(withTitle: "취소")

        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .adoptTarget
        case .alertSecondButtonReturn: return .copyCurrent
        default:                       return nil
        }
    }

    /// 홈 디렉터리 접두사를 ~로 줄여 경로를 읽기 쉽게 만든다.
    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func showError(_ error: Error, title: String = "저장 위치를 변경할 수 없습니다") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
