import ServiceManagement
import SwiftUI

/// ⌘,로 여는 설정 창.
///
/// 계정 목록 창과 **다른 창**이다. macOS에서 ⌘,는 "앱 환경설정"이라는 뜻이 고정된
/// 단축키이고, 계정 목록은 환경설정이 아니라 앱의 내용이다. 한 창에 둘을 같이 넣었더니
/// 설정을 고를 때마다 분할 뷰를 통째로 갈아 끼워야 했고, 그때 AppKit이 저장해 둔 분할선
/// 위치가 복원되면서 계정 목록 열이 쪼그라들었다 — 창을 나누면 그 문제가 원인째 없어진다.
///
/// 사이드바를 두는 건 갈래가 셋이기 때문이다. 하나짜리 폼에 전부 쌓아 두면 저장 위치처럼
/// 위험한 항목이 로그인 토글 바로 밑에 붙는다.
struct SettingsWindowView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, storage, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "일반"
            case .storage: "저장"
            case .about: "정보"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .storage: "externaldrive"
            case .about: "info.circle"
            }
        }
    }

    @State private var pane: Pane = .general

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch pane {
                case .general: GeneralSettingsView()
                case .storage: StorageSettingsView()
                case .about: AboutSettingsView()
                }
            }
            // 오른쪽은 남는 폭을 다 쓴다. 폭을 고정해 뒀더니 창이 그보다 넓을 때 내용이
            // 가운데 좁게 뭉치고 양쪽이 비었다.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle(pane.title)
        // 처음 크기는 `Settings` 씬 기본값에 맡긴다. 최소치만 지켜 준다 — 이보다 좁아지면
        // 태그 색상 스와치 여덟 개가 라벨을 밀어낸다.
        .frame(minWidth: 440, minHeight: 300)
    }

    /// 계정 창 사이드바와 같은 모양을 쓴다 — 위에 로고, 그 아래 목록. 두 창이 한 앱이라는
    /// 걸 사이드바가 말해 준다.
    private var sidebar: some View {
        List(selection: Binding(
            get: { pane },
            // 빈 곳을 눌러 선택이 풀리면 오른쪽이 비어 버린다. 설정 창에는 "아무것도 안 고른
            // 상태"가 없으므로 해제는 무시한다.
            set: { if let new = $0 { pane = new } }
        )) {
            Section {
                ForEach(Pane.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
        }
        // 갈래가 셋뿐이라 폭이 변할 이유가 없다. 늘릴 수 있게 두면 사이드바만 넓어진다.
        .navigationSplitViewColumnWidth(160)
        // 설정 창의 사이드바는 접지 않는다(시스템 설정도 그렇다). 토글을 남겨 두면 툴바가
        // 없는 타이틀바 한가운데에 버튼 하나가 떠 있는다.
        .toolbar(removing: .sidebarToggle)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                logoTitle
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    /// 계정 창과 같은 로고. 배경 없는 단색 픽셀-Q(메뉴바 아이콘과 동일한 template 에셋)라
    /// 라이트/다크 모드의 라벨 색을 자동으로 따라간다.
    private var logoTitle: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .interpolation(.none)
            .frame(width: 18, height: 18)
            .foregroundStyle(.primary)
            .accessibilityLabel("Qr2fa")
    }
}

/// 설정 창의 **일반** 갈래.
struct GeneralSettingsView: View {
    @Environment(TagStyle.self) private var tagStyle
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("로그인 시 시작", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { _, newValue in
                        setStartAtLogin(newValue)
                    }
                LabeledContent("태그 색상") { tagColorSwatches }
            }
        }
        .formStyle(.grouped)
    }

    /// 태그 색 고르기. 색은 태그마다가 아니라 **전체에 하나**다 — 태그는 이름으로 읽는
    /// 것이고, 색이 여럿이면 뜻 없는 규칙을 외우게 된다. 여기서 고르는 건 그 하나다.
    private var tagColorSwatches: some View {
        HStack(spacing: 6) {
            ForEach(TagColorToken.allCases) { token in
                Button {
                    tagStyle.token = token
                } label: {
                    Circle()
                        .fill(token.color)
                        .frame(width: 16, height: 16)
                        // 고른 것에 테두리를 두른다. 체크 표시는 16pt 원 안에서 뭉개진다.
                        .overlay {
                            Circle()
                                .strokeBorder(.primary, lineWidth: 2)
                                .padding(-3)
                                .opacity(tagStyle.token == token ? 1 : 0)
                        }
                }
                .buttonStyle(.plain)
                .help(token.label)
                .accessibilityLabel(token.label)
                .accessibilityAddTraits(tagStyle.token == token ? [.isSelected] : [])
            }
        }
        // 테두리가 원 밖으로 3pt 나가므로 그만큼 자리를 비워 둔다.
        .padding(.vertical, 3)
        .animation(.easeOut(duration: 0.15), value: tagStyle.token)
    }

    private func setStartAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 실패했으면 토글을 되돌린다 — 켜진 채로 두면 등록된 줄 안다.
            startAtLogin = !enabled
            let alert = NSAlert()
            alert.messageText = "로그인 항목 설정을 변경할 수 없습니다"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

/// 설정 창의 **정보** 갈래.
struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appDisplayName)
                            .font(.system(size: 30, weight: .semibold))
                        Text("Version \(appVersionString)")
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
}
