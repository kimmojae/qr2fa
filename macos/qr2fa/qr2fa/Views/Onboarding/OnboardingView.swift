import AppKit
import SwiftUI

/// 첫 실행 때 MFA 데이터 저장 위치를 고르는 화면.
/// 저장 위치 하나만 묻는다 — 화면 기록 권한이나 기능 소개는 넣지 않는다.
struct OnboardingView: View {
    @Environment(StorageService.self) private var storageService

    /// 확정에 성공했을 때 호출된다. 실패하면 호출하지 않고 이 화면에 머문다.
    let onFinish: () -> Void

    // iCloud를 쓸 수 없는 Mac에서는 "이 Mac에만 저장"으로 시작한다.
    @State private var choice: StorageLocationChoice =
        StorageService.iCloudDirectory() == nil ? .local : .iCloud
    @State private var customDirectory: String?

    private let iCloudDirectory = StorageService.iCloudDirectory()

    private var selectedDirectory: String? {
        switch choice {
        case .iCloud: return iCloudDirectory
        case .local:  return storageService.defaultDirectory
        case .custom: return customDirectory
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MFA 데이터를 어디에 저장할까요?")
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Form {
                Section {
                    StorageLocationPicker(
                        selection: $choice,
                        iCloudAvailable: iCloudDirectory != nil
                    )
                }

                Section {
                    LabeledContent("저장 폴더") {
                        HStack(spacing: 8) {
                            Text(selectedDirectory.map(abbreviateHome) ?? "선택되지 않음")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            // 이미 custom인 상태에서 다른 폴더로 바꿀 수 있는 유일한 통로.
                            // Picker 선택이 이미 .custom이라 onChange가 다시 안 걸린다.
                            if choice == .custom {
                                Button("변경…") { pickCustomDirectory() }
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
                    .disabled(selectedDirectory == nil)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onChange(of: choice) { oldValue, newValue in
            guard newValue == .custom else { return }
            presentDirectoryPicker { directory in
                if let directory {
                    customDirectory = directory
                } else {
                    choice = oldValue   // 패널을 취소하면 직전 선택으로 되돌린다
                }
            }
        }
    }

    // MARK: - Actions

    private func pickCustomDirectory() {
        presentDirectoryPicker { directory in
            if let directory {
                customDirectory = directory
            }
        }
    }

    private func commit() {
        guard let directory = selectedDirectory else { return }
        do {
            let outcome = try storageService.commitInitialLocation(directory: directory)
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

    /// 확정은 됐지만 사용자가 알아야 하는 것들 — 로드 실패, 그리고 이전 위치에 남은 계정.
    private func showNotice(_ outcome: StorageService.CommitOutcome) {
        var lines: [String] = []

        if let path = outcome.leftBehindPath {
            lines.append("""
                선택한 폴더에 이미 계정 파일이 있어 그쪽을 그대로 씁니다.
                이전 위치에 계정 \(outcome.leftBehindCount)개가 남아 있습니다:
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

        let alert = NSAlert()
        alert.messageText = "저장 위치를 설정했습니다"
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.alertStyle = .warning
        alert.runModal()
    }
}
