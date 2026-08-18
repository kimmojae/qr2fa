import AppKit
import SwiftUI

/// 첫 실행 때 MFA 데이터 저장 위치를 고르는 화면.
/// 저장 위치 하나만 묻는다 — 화면 기록 권한이나 기능 소개는 넣지 않는다.
///
/// 폴더 선택은 **옵션**이다. 고르지 않으면 이 Mac의 기본 폴더를 쓴다. 예전엔 iCloud Drive /
/// 이 Mac / 직접 선택… 3지선다였는데, 셋 다 결국 "폴더 하나"였고 직접 선택이 나머지 둘을
/// 포함해서 동급 선택지처럼 보이는 게 실제로 겹쳐 보였다. 동기화하고 싶은 사람은 그 폴더를
/// (iCloud든 Dropbox든) 직접 고르면 된다.
struct OnboardingView: View {
    @Environment(StorageService.self) private var storageService

    /// 확정에 성공했을 때 호출된다. 실패하면 호출하지 않고 이 화면에 머문다.
    let onFinish: () -> Void

    /// nil이면 기본 폴더(이 Mac)를 쓴다.
    @State private var customDirectory: String?

    private var selectedDirectory: String {
        customDirectory ?? storageService.defaultDirectory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 앱을 처음 보는 화면이라 아이콘과 이름을 함께 둔다 — 창 제목만으로는
            // 어느 앱이 폴더를 묻는지 알기 어렵다.
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appDisplayName)
                        .font(.system(size: 16, weight: .semibold))
                    Text("MFA 데이터를 어디에 저장할까요?")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Form {
                Section {
                    LabeledContent("저장 폴더") {
                        HStack(spacing: 8) {
                            Text(abbreviateHome(selectedDirectory))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button(customDirectory == nil ? "선택…" : "변경…") {
                                pickDirectory()
                            }
                            if customDirectory != nil {
                                Button("기본값으로") { customDirectory = nil }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Text("나중에 설정 > 일반에서 바꿀 수 있습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("시작하기") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Actions

    private func pickDirectory() {
        presentDirectoryPicker { directory in
            // 고른 폴더 그대로가 아니라 그 안의 데이터 폴더를 쓴다 — 확정 전에 화면에서
            // 최종 경로를 볼 수 있어야 한다.
            if let directory { customDirectory = StorageService.dataDirectory(inside: directory) }
        }
    }

    private func commit() {
        do {
            let outcome = try storageService.commitInitialLocation(directory: selectedDirectory)
            // 위치는 이미 고정됐다. 알릴 게 있어도 창은 닫는다 — 여기서 멈추면 다시 눌러도
            // 같은 상태라 같은 경고가 무한 반복되고, 창을 강제로 닫는 것 말고 탈출구가 없다.
            if outcome.hasNotice { showNotice(outcome) }
            onFinish()
        } catch {
            // 위치 고정 자체가 실패한 경우에만 이 화면에 머문다(다시 시도할 여지가 있다).
            let alert = NSAlert()
            alert.messageText = "저장 위치를 설정할 수 없습니다"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    /// 예정대로 되지 않은 것만 알린다 — 정상적으로 끝난 확정은 조용히 창을 닫는다.
    private func showNotice(_ outcome: StorageService.CommitOutcome) {
        var lines: [String] = []

        if let path = outcome.leftBehindPath {
            lines.append("""
                선택한 폴더에 이미 계정 파일이 있어 그쪽을 그대로 씁니다.
                여기까지 등록한 계정 \(outcome.leftBehindCount)개는 이전 위치에 남았습니다:
                \(abbreviateHome(path))
                필요하면 Finder에서 직접 옮기세요 — 자동으로 지우지 않습니다.
                """)
        }
        if let error = outcome.loadError {
            lines.append("""
                저장 위치의 파일을 읽지 못했습니다:
                \(error.localizedDescription)
                설정 > 일반에서 다른 위치를 고를 수 있습니다.
                """)
        }
        guard !lines.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "저장 위치는 설정했습니다"
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.alertStyle = .warning
        alert.runModal()
    }
}
