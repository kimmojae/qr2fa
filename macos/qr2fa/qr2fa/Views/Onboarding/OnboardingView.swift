import AppKit
import SwiftUI

/// 첫 실행 때 MFA 데이터 저장 위치를 고르는 화면.
/// 저장 위치 하나만 묻는다 — 화면 기록 권한이나 기능 소개는 넣지 않는다.
struct OnboardingView: View {
    @Environment(StorageService.self) private var storageService

    /// 확정에 성공했을 때 호출된다. 실패하면 호출하지 않고 이 화면에 머문다.
    let onFinish: () -> Void

    enum Choice: Hashable { case iCloud, local, custom }

    // iCloud를 쓸 수 없는 Mac에서는 "이 Mac에만 저장"으로 시작한다.
    @State private var choice: Choice =
        StorageService.iCloudDirectory() == nil ? .local : .iCloud
    @State private var customDirectory: String?

    private let iCloudDirectory = StorageService.iCloudDirectory()
    private let localDirectory = StorageService.localDefaultDirectory()

    private var selectedDirectory: String? {
        switch choice {
        case .iCloud: return iCloudDirectory
        case .local:  return localDirectory
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
                    Picker("", selection: $choice) {
                        row(
                            "iCloud Drive",
                            iCloudDirectory == nil
                                ? "iCloud Drive가 꺼져 있습니다"
                                : "다른 Mac에서도 같은 계정이 보입니다"
                        )
                        .disabled(iCloudDirectory == nil)
                        .tag(Choice.iCloud)

                        row("이 Mac에만 저장", "이 Mac 밖으로 나가지 않습니다")
                            .tag(Choice.local)

                        row("직접 선택…", "Dropbox 등 원하는 폴더")
                            .tag(Choice.custom)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }

                Section {
                    LabeledContent("저장 폴더") {
                        HStack(spacing: 8) {
                            Text(selectedDirectory.map(abbreviate) ?? "선택되지 않음")
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
            if let directory = promptForDirectory() {
                customDirectory = directory
            } else {
                choice = oldValue   // 패널을 취소하면 직전 선택으로 되돌린다
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    /// 홈 디렉터리 접두사를 ~로 줄여 경로를 읽기 쉽게 만든다.
    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Actions

    /// 취소하면 nil. GeneralSettingsView.changeLocation()과 같은 패널 설정을 쓴다.
    private func promptForDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "선택"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    private func pickCustomDirectory() {
        if let directory = promptForDirectory() {
            customDirectory = directory
        }
    }

    private func commit() {
        guard let directory = selectedDirectory else { return }
        do {
            try storageService.commitInitialLocation(directory: directory)
            onFinish()
        } catch {
            let alert = NSAlert()
            alert.messageText = "저장 위치를 설정할 수 없습니다"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
