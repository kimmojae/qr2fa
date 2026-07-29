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

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: storageService.storagePath)])
    }

    // MARK: - Location change

    /// 저장 폴더를 직접 고른다. 앱의 기본 iCloud 위치(`.qr2fa`)는 숨김 폴더라
    /// `presentDirectoryPicker`가 숨김 파일을 보이게 해 둔다.
    private func changeLocation() {
        presentDirectoryPicker { directory in
            if let directory { moveStorage(to: directory) }
        }
    }

    /// 저장 폴더를 옮기는 단일 통로.
    ///
    /// 대상 폴더에 다른 계정 파일이 있으면 조용히 덮어쓰지 않는다 — 어느 쪽을 정본으로 삼을지
    /// 반드시 사용자에게 묻는다. 여러 Mac에서 각자 계정을 등록한 뒤 iCloud로 합치는 건
    /// 정상 사용 패턴이고, 그 순간 잘못 고르면 복구 불가능한 MFA 시크릿이 날아간다.
    private func moveStorage(to directory: String) {
        let target = "\(directory)/accounts.json"

        let strategy: StorageService.PathChangeStrategy
        switch StorageLocationDecision.decide(
            currentPath: storageService.storagePath, targetPath: target
        ) {
        case .noChange:
            return
        case .proceed(let decided):
            strategy = decided
        case .askWhichWins(let count):
            guard let choice = askWhichFileWins(directory: directory, targetCount: count) else { return }
            strategy = choice
        case .askOverwriteUnreadable:
            guard confirmOverwriteUnreadable(target: target) else { return }
            strategy = .copyCurrent
        }

        do {
            let outcome = try storageService.changePath(to: target, strategy: strategy)
            if outcome.hasNotice { showNotice(outcome) }
        } catch {
            showError(error)
        }
    }

    private func confirmOverwriteUnreadable(target: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "선택한 폴더에 읽을 수 없는 accounts.json이 있습니다"
        alert.informativeText = """
            \(abbreviateHome(target))

            계속하면 그 파일을 accounts.json.bak-<시각>으로 백업한 뒤 현재 계정 \
            \(storageService.accounts.count)개로 새로 씁니다.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "백업 후 계속")
        alert.addButton(withTitle: "취소")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 대상에 계정 파일이 있을 때 어느 쪽을 정본으로 삼을지 묻는다. 취소면 nil.
    private func askWhichFileWins(
        directory: String,
        targetCount: Int
    ) -> StorageService.PathChangeStrategy? {
        let alert = NSAlert()
        alert.messageText = "선택한 폴더에 이미 계정 파일이 있습니다"
        alert.informativeText = """
            \(abbreviateHome(directory))/accounts.json — 계정 \(targetCount)개
            현재 위치 — 계정 \(storageService.accounts.count)개

            어느 쪽을 계속 쓸지 고르세요. 덮어쓰기를 고르면 그 폴더의 기존 파일은 \
            accounts.json.bak-<시각>으로 백업합니다.
            """
        alert.alertStyle = .warning
        // 기본 버튼은 아무것도 덮지 않는 쪽으로 둔다.
        alert.addButton(withTitle: "그 폴더의 파일 사용")
        alert.addButton(withTitle: "현재 계정으로 덮어쓰기")
        alert.addButton(withTitle: "취소")
        // 3버튼 알럿에서는 세 번째 버튼에 Esc가 자동으로 걸리지 않는다.
        alert.buttons[2].keyEquivalent = "\u{1b}"

        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .adoptTarget
        case .alertSecondButtonReturn: return .copyCurrent
        default:                       return nil
        }
    }

    /// 옮긴 뒤 사용자가 알아야 하는 것들 — 백업 파일, 이전 위치에 남은 파일, 로드 실패.
    private func showNotice(_ outcome: StorageService.PathChangeOutcome) {
        var lines: [String] = []

        if let backup = outcome.backupPath {
            lines.append("""
                그 폴더에 있던 파일은 다음 이름으로 백업했습니다:
                \(abbreviateHome(backup))
                """)
        }
        if let left = outcome.leftBehindPath {
            lines.append("""
                이전 위치에 계정 \(outcome.leftBehindCount)개가 그대로 남아 있습니다:
                \(abbreviateHome(left))
                자동으로 지우지 않습니다. 그대로 두면 지금부터 두 파일이 따로 갈라지고, \
                그 폴더가 iCloud라면 다른 Mac은 갱신이 멈춘 옛 데이터를 계속 보게 됩니다.
                """)
        }
        if let error = outcome.loadError {
            lines.append("""
                새 위치의 파일을 읽지 못했습니다:
                \(error.localizedDescription)
                """)
        }

        let alert = NSAlert()
        alert.messageText = "저장 위치를 바꿨습니다"
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.alertStyle = outcome.loadError == nil ? .informational : .warning
        alert.runModal()
    }

    private func showError(_ error: Error, title: String = "저장 위치를 변경할 수 없습니다") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
