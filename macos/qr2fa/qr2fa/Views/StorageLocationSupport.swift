import AppKit

/// 홈 디렉터리 접두사를 `~`로 줄여 경로를 읽기 쉽게 만든다.
func abbreviateHome(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

/// 폴더 선택 패널을 띄우고 고른 경로를 돌려준다.
///
/// 온보딩과 설정 > 일반이 저장 위치를 고르는 **유일한 통로**다. iCloud Drive든 Dropbox든
/// "폴더를 고른다" 하나로 합쳐 두면, 선택지를 미리 나열하지 않아도 되고 나열하지 않은 위치를
/// 고를 수 없는 문제도 생기지 않는다.
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
        // 앱이 예전에 기본으로 쓰던 iCloud 위치가 숨김 폴더(.qr2fa)다. 이걸 켜지 않으면
        // 패널에서 그리로 돌아갈 방법이 없어, 이미 그 폴더를 쓰는 사용자가 막힌다.
        panel.showsHiddenFiles = true
        completion(panel.runModal() == .OK ? panel.url?.path : nil)
    }
}
