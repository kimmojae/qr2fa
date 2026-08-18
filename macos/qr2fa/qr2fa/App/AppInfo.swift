import Foundation

/// 앱 이름/버전은 온보딩 헤더와 설정 > 일반의 정보 영역 두 곳에서 쓴다. Info.plist 키를
/// 양쪽에서 따로 읽으면 한쪽만 바뀌어도 두 화면이 다른 이름을 보여줄 수 있으니 여기서만 읽는다.
var appDisplayName: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Qr2fa"
}

var appVersionString: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
}
