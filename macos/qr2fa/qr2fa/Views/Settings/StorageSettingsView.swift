import SwiftUI

/// 설정 창의 **저장** 갈래. 계정 파일이 어디 있는지 보여주고 옮긴다.
///
/// 옮기는 일은 되돌릴 수 없는 MFA 시크릿을 다루므로, 이 파일의 알림 문구와 분기는
/// `StorageServiceTests`가 지키는 규칙과 짝이다 — 손대기 전에 그쪽을 먼저 읽는 게 좋다.
struct StorageSettingsView: View {
    @Environment(StorageService.self) private var storageService
    @State private var showingLocationInfo = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    // 한 줄로 두고 가운데를 줄인다. 두 줄을 허용했더니 iCloud 경로가 줄을
                    // 넘기면서 라벨과 어긋나 보였다. 앞뒤(홈 표기와 파일명)는 남고 중간
                    // 폴더만 줄어드는 게 이 값에서 가장 알아보기 쉽다 — 전체는 툴팁과
                    // 드래그 선택으로 볼 수 있다.
                    Text(abbreviateHome(storageService.storagePath))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(storageService.storagePath)
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
                        .accessibilityLabel("저장 위치 설명 보기")
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
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: storageService.storagePath)])
    }

    // MARK: - Location change

    /// 저장 폴더를 직접 고른다. 앱의 기본 iCloud 위치(`.qr2fa`)는 숨김 폴더라
    /// `presentDirectoryPicker`가 숨김 파일을 보이게 해 둔다.
    private func changeLocation() {
        presentDirectoryPicker { directory in
            // 고른 폴더 안의 데이터 폴더(.qr2fa)로 옮긴다 — 동기화 폴더 최상위에 시크릿
            // 파일이 문서들 옆에 놓이지 않게 하는 건 사용자가 아니라 앱이 할 일이다.
            if let directory {
                moveStorage(to: StorageService.dataDirectory(inside: directory))
            }
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

    /// 예정대로 되지 않은 것만 알린다. 성공은 경로 줄이 바뀐 것으로 충분하다.
    private func showNotice(_ outcome: StorageService.PathChangeOutcome) {
        var lines: [String] = []

        if let left = outcome.leftBehindPath {
            lines.append("""
                이전 위치의 계정 파일(계정 \(outcome.leftBehindCount)개)을 예전 버전으로 \
                표시하지 못했습니다:
                \(abbreviateHome(left))
                그대로 두면 지금부터 두 파일이 따로 갈라지고, 그 폴더가 iCloud라면 다른 Mac은 \
                갱신이 멈춘 옛 데이터를 계속 보게 됩니다.
                """)
        }
        if let error = outcome.loadError {
            lines.append("""
                새 위치의 파일을 읽지 못했습니다:
                \(error.localizedDescription)
                """)
        }
        guard !lines.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "저장 위치는 바꿨습니다"
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.alertStyle = .warning
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
