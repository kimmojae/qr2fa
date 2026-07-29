import SwiftUI

/// 저장 위치 선택지.
///
/// 온보딩과 설정 > 일반이 **같은 결정을 같은 모양으로** 제시해야 한다. 설정에 원시 폴더
/// 패널만 두면 앱의 기본 iCloud 위치(`.qr2fa` — 숨김 폴더)로 돌아갈 방법이 아예 없어서,
/// 사용자는 iCloud Drive 루트를 고르게 되고 시크릿 파일이 다른 문서들 옆에 놓인다.
enum StorageLocationChoice: Hashable {
    case iCloud
    case local
    case custom

    /// 지금 쓰고 있는 폴더가 셋 중 어디에 해당하는지. 어느 것도 아니면 `.custom`.
    static func matching(directory: String, localDirectory: String) -> StorageLocationChoice {
        if directory == StorageService.iCloudDirectory() { return .iCloud }
        if directory == localDirectory { return .local }
        return .custom
    }
}

/// 라디오 3선택지. 두 화면이 이 목록을 공유한다.
///
/// 공유하는 건 **선택지 자체**뿐이다 — 온보딩은 `.frame` 고정 창이고 설정은 리사이즈되는
/// 폼이라 바깥 레이아웃은 각자 정한다. 선택이 바뀌었을 때 무엇을 할지도 각자 다르다
/// (온보딩은 확정 전까지 고르기만, 설정은 즉시 파일을 옮긴다).
struct StorageLocationPicker: View {
    @Binding var selection: StorageLocationChoice
    let iCloudAvailable: Bool

    var body: some View {
        Picker("", selection: $selection) {
            row(
                "iCloud Drive",
                iCloudAvailable
                    ? "다른 Mac에서도 같은 계정이 보입니다"
                    : "iCloud Drive가 꺼져 있습니다"
            )
            .disabled(!iCloudAvailable)
            .tag(StorageLocationChoice.iCloud)

            row("이 Mac에만 저장", "이 Mac 밖으로 나가지 않습니다")
                .tag(StorageLocationChoice.local)

            row("직접 선택…", "Dropbox 등 원하는 폴더")
                .tag(StorageLocationChoice.custom)
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
    }

    @ViewBuilder
    private func row(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

/// 홈 디렉터리 접두사를 `~`로 줄여 경로를 읽기 쉽게 만든다.
func abbreviateHome(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

/// 폴더 선택 패널을 띄우고 고른 경로를 돌려준다.
///
/// 다음 런루프 틱으로 미루는 이유: SwiftUI의 상태 갱신 트랜잭션(`.onChange`, Binding setter)
/// 도중에 `runModal()`을 곧바로 부르면 패널이 아예 뜨지 않을 수 있다. 이 앱은 LSUIElement
/// (액세서리) 앱이라 전면에 활성화돼 있지 않으면 패널이 뒤로 밀리므로 활성화도 먼저 한다.
func presentDirectoryPicker(completion: @escaping (String?) -> Void) {
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "선택"
        completion(panel.runModal() == .OK ? panel.url?.path : nil)
    }
}
