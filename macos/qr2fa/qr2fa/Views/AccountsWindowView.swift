import SwiftUI

/// 사이드바에서 고를 수 있는 것. 예전엔 `"__all__"` 센티넬 문자열을
/// issuer 이름과 같은 `String?` 자리에 섞어 썼는데, 그러면 "지금 고른 게 서비스인가"를
/// 판단하는 규칙이 코드 곳곳에 흩어진다. 타입으로 못 박으면
/// 그 판단이 `switch` 한 곳으로 모이고, issuer 이름이 우연히 센티넬과 겹칠 여지도 없다.
enum SidebarItem: Hashable {
    case allAccounts
    case issuer(String)

    /// 고른 게 특정 서비스일 때 그 이름. 모든 계정이면 nil.
    var issuerName: String? {
        if case .issuer(let name) = self { return name }
        return nil
    }
}

/// Where the sidebar should land right after accounts were added.
enum AddedAccountFocus {
    /// The sidebar row that shows *all* of `added`, or `nil` when nothing was added.
    /// A mixed import has no such row, so it falls back to 모든 계정 — sending it to
    /// one service would hide the rest of what the user just imported.
    static func destination(for added: [Account]) -> SidebarItem? {
        guard let first = added.first else { return nil }
        let issuers = Set(added.map(\.displayIssuer))
        return issuers.count == 1 ? .issuer(first.displayIssuer) : .allAccounts
    }
}

struct AccountsWindowView: View {
    @Environment(StorageService.self) private var storageService
    @State private var selection: SidebarItem? = .allAccounts
    @State private var selectedAccountID: Int? = nil
    @State private var showingAddSheet = false
    @State private var isEditingAccount: Bool = false
    @State private var scrollTarget: Int?
    @State private var searchText = ""
    /// 상세 열의 인증 코드와 남은 시간 링이 쓰는 "지금". 앱 전체가 시계 하나를 나눠 쓴다 —
    /// 메뉴바 패널과 나란히 띄웠을 때 남은 시간이 어긋나면 안 된다.
    @Environment(TOTPClock.self) private var clock

    private var now: Date { clock.now }

    private var issuers: [String] {
        AccountOrdering.issuers(in: storageService.accounts)
    }

    private var listedAccounts: [Account] {
        let scoped = selectedService.map { issuer in
            storageService.accounts.filter { $0.displayIssuer == issuer }
        } ?? storageService.accounts
        return AccountSearch.filter(scoped, query: searchText)
    }

    private var selectedAccount: Account? {
        guard let id = selectedAccountID else { return nil }
        return storageService.accounts.first { $0.id == id }
    }

    // 사이드바에서 선택한 항목의 이름 — 둘째 열(계정 목록) 상단 제목으로 쓴다.
    private var contentTitle: String { selectedService ?? "모든 계정" }

    /// 창 하나에 분할 뷰 **하나**. 설정은 ⌘,로 여는 딴 창(`SettingsWindowView`)이다.
    ///
    /// 예전엔 사이드바에 "일반"이 있어서, 그걸 고르면 2열짜리 분할 뷰로 통째로 갈아 끼웠다
    /// (3열에서는 가운데 열을 숨길 수 없어서). 그런데 분할선 위치는 AppKit이 창 단위로
    /// 저장하기 때문에, 2열이 덮어쓴 값을 3열이 다시 지어질 때 복원해 버려서 계정 목록 열이
    /// 200pt로 쪼그라들었다. 열 폭 수식어의 `ideal`은 물론 `min`도 그걸 못 이기고, SwiftUI에는
    /// 그 저장을 끄거나 폭을 직접 넣을 API가 없다. 안 부수면 복원할 일도 없다 — 드래그로
    /// 바꾼 폭이 그대로 남는 것도 같은 이유다.
    var body: some View {
        NavigationSplitView {
                    sidebarView
                } content: {
                    ScrollViewReader { proxy in
                    // 빈 공간 클릭 등으로 들어오는 nil(선택 해제)은 무시한다.
                    // 원본 State가 안 바뀌므로 해제→복원 왕복이 없고, 탭 깜빡임도 안 생긴다.
                    List(selection: Binding(
                        get: { selectedAccountID },
                        set: { if let newValue = $0 { selectedAccountID = newValue } }
                    )) {
                        ForEach(listedAccounts) { account in
                            AccountRowView(account: account)
                                .tag(account.id)
                                .id(account.id)
                        }
                        .onMove(perform: selectedService == nil ? nil : moveAccounts(from:to:))
                    }
                    .onChange(of: scrollTarget) { _, target in
                        // 목록이 새 선택으로 갱신된 다음에 스크롤해야 대상 행이 존재한다.
                        guard let target else { return }
                        DispatchQueue.main.async {
                            withAnimation { proxy.scrollTo(target) }
                            scrollTarget = nil
                        }
                    }
                    .listStyle(.inset)
                    .navigationTitle(contentTitle)
                    // 제목 아래 부제목 — 지금 목록에 몇 개가 있는지. 검색 중이면 걸러진
                    // 개수라 "몇 개가 걸렸는지"가 바로 보인다.
                    .navigationSubtitle(listedAccounts.isEmpty ? "계정 없음"
                                                               : "계정 \(listedAccounts.count)개")
                    .onChange(of: selectedAccountID) { oldValue, _ in
                        isEditingAccount = false
                        // 항상 계정 하나는 선택된 상태를 유지한다. 빈 공간 클릭 등으로 선택이
                        // 해제되면 직전 선택(아직 존재하면)이나 목록의 첫 계정으로 되돌린다.
                        if selectedAccountID == nil {
                            let restore = oldValue.flatMap { id in
                                listedAccounts.contains { $0.id == id } ? id : nil
                            } ?? listedAccounts.first?.id
                            if restore != nil {
                                selectedAccountID = restore
                            }
                        }
                    }
                    }
                    // 폭을 **정확한 값 하나로** 못 박는다. `min:ideal:`로 줬더니 일반(2열)에
                    // 다녀올 때마다 200pt로 쪼그라들었다 — 분할선 위치는 AppKit이 창 단위로
                    // 저장하는데, 2열이 덮어쓴 값을 3열이 다시 지어질 때 복원해 버리고,
                    // `ideal`은 물론이고 `min`도 그걸 못 이겼다. 최소와 최대가 같으면
                    // 복원할 여지 자체가 없다. 그 대신 이 열은 드래그로 못 늘린다.
                    // 열 폭은 **열의 최상위 뷰**에 붙어야 전달된다. 안쪽 List에 붙였더니
                    // 조용히 무시돼서 저장된 배치(200pt)가 그대로 이겼다 — 계정 이름이
                    // 이메일이라 그 폭에서는 대부분 잘린다.
                    .navigationSplitViewColumnWidth(min: 300, ideal: 360)
                    // 검색은 이 목록을 거르는 동작이라 목록 열에 둔다. 상세 열에 붙여 봤지만
                    // (암호 앱이 거기 두길래) 아예 렌더링되지 않았다.
                    .searchable(text: $searchText, placement: .automatic, prompt: "계정 검색")
                    .toolbar { listToolbar }
                } detail: {
                    if let account = selectedAccount {
                        AccountDetailView(account: account, now: now, isEditing: $isEditingAccount) {
                            selectedAccountID = nil
                            isEditingAccount = false
                        }
                        .environment(storageService)
                        // 편집은 상세에 보이는 그 계정을 고치는 동작이라 **상세 열**에 둔다.
                        // 툴바를 분할 뷰가 아니라 각 열의 뷰 안쪽에 붙여야 SwiftUI가 분할
                        // 구분선에 맞춰 툴바를 구역으로 나눈다. 하나라도 분할 뷰 레벨에
                        // 붙으면 전부 창 툴바로 합쳐진다.
                        //
                        // 항목을 구역의 **뒤쪽**으로 보내는 방법은 못 찾았다. 시도한 것들:
                        // `.primaryAction` 배치(무시됨), 앞에 `frame(maxWidth: .infinity)`인
                        // 항목 두기(툴바 항목은 내용 크기로 잡혀 안 늘어남), `navigationTitle`
                        // (상세 열에는 인라인으로 안 그려진다 — 분할 뷰의 `navigationTitle("")`
                        // 때문인가 싶어 지워 보기도 했지만 그것과는 무관했다. 이유는 모른다).
                        // 빈 공간을 미는 `ToolbarSpacer`는 macOS 26부터라 배포 타깃(14.0)에선
                        // 못 쓴다. 암호 앱도 상세 열의 공유·편집은 왼쪽이고, 오른쪽 끝은
                        // 검색 필드가 실제 내용으로 채운다.
                        .toolbar {
                            // 열 구역 안에서는 항목이 앞쪽부터 채워진다. `.primaryAction`도,
                            // 앞에 `frame(maxWidth: .infinity)`인 항목을 두는 것도 통하지
                            // 않는다 — 툴바 항목은 내용 크기로 잡힌다. 빈 공간을 밀어내는
                            // `ToolbarSpacer`는 macOS 26부터라 지금 배포 타깃(14.0)에선 못 쓴다.
                            // 암호 앱도 상세 열의 공유·편집이 왼쪽에 붙어 있고, 오른쪽 끝은
                            // 검색 필드가 실제 내용으로 채우고 있다.
                            ToolbarItem {
                                if isEditingAccount {
                                    Button("편집 취소") { isEditingAccount = false }
                                } else {
                                    Button("편집") { isEditingAccount = true }
                                        .help("계정 편집")
                                }
                            }
                        }
                    } else {
                        // 여기까지 오는 건 계정이 하나도 없을 때뿐이다(항상 자동 선택되므로).
                        ContentUnavailableView(
                            "계정이 없습니다",
                            systemImage: "person.crop.circle.badge.plus",
                            description: Text("오른쪽 위 + 버튼으로 계정을 추가하세요.")
                        )
                    }
                }
        .navigationTitle("")
        .sheet(isPresented: $showingAddSheet) {
            AccountAddSheet { added in
                focus(on: added)
            }
            .environment(storageService)
        }
        .onAppear {
            if selectedAccountID == nil {
                selectedAccountID = listedAccounts.first?.id
            }
        }
        .onDisappear {
            // 창을 닫을 때 상태를 초기화해서, 다음에 열 때는 항상 "모든 계정"에서 시작하게 한다.
            selection = .allAccounts
            selectedAccountID = nil
            isEditingAccount = false
        }
        .onChange(of: issuers) {
            // 서비스 목록은 계정에서 파생된다 — 마지막 계정이 사라지면(삭제, CLI 쪽 편집,
            // issuer 이름 변경) 그 서비스는 사이드바에서 없어지는데, 선택은 사라진 이름을
            // 그대로 붙들고 있어 "빈 서비스"가 선택된 것처럼 보인다.
            // 그런 상태가 되면 "모든 계정"으로 되돌린다.
            guard let issuer = selectedService, !issuers.contains(issuer) else { return }
            selection = .allAccounts
        }
        .onChange(of: selection) {
            // 서비스 그룹을 바꾸면 편집 상태를 끈다. 계정 선택은 이미 그 그룹에 속한 계정이
            // 선택돼 있으면 건드리지 않는다 — 계정을 추가한 직후 새 계정으로 보내는 이동이
            // 여기서 그 그룹의 첫 계정으로 되돌려지면 안 된다.
            isEditingAccount = false
            if !listedAccounts.contains(where: { $0.id == selectedAccountID }) {
                selectedAccountID = listedAccounts.first?.id
            }
        }
    }

    /// The service whose accounts are on screen, or nil for 모든 계정.
    ///
    /// Account drag-reordering is offered only inside a service: dragging across service
    /// boundaries in 모든 계정 would move a service's first account, and service order is
    /// derived from exactly that position — the sidebar would reshuffle unpredictably.
    private var selectedService: String? { selection?.issuerName }

    private func moveAccounts(from source: IndexSet, to destination: Int) {
        guard let issuer = selectedService else { return }
        let reordered = AccountOrdering.movingAccounts(
            in: storageService.accounts, issuer: issuer, from: source, to: destination
        )
        try? storageService.reorder(to: reordered)
    }

    /// Drag-reordering the service rows rewrites the stored account order, which is
    /// what the menu bar reads too.
    private func moveIssuers(from source: IndexSet, to destination: Int) {
        let reordered = AccountOrdering.movingIssuers(
            in: storageService.accounts, from: source, to: destination
        )
        try? storageService.reorder(to: reordered)
    }

    /// Shows what was just added: the service tab that covers all of it, with the
    /// first new account selected and scrolled into view.
    private func focus(on added: [Account]) {
        guard let destination = AddedAccountFocus.destination(for: added),
              let first = added.first else { return }
        isEditingAccount = false
        selectedAccountID = first.id
        selection = destination
        // A List does not scroll to a selection that changed in code.
        scrollTarget = first.id
    }

    private var logoTitle: some View {
        // 배경 없는 단색 픽셀-Q(메뉴바 아이콘과 동일한 template 에셋).
        // template 렌더링이라 라이트/다크 모드의 라벨 색을 자동으로 따라간다.
        // 툴바가 아니라 사이드바 콘텐츠에 두므로 버튼 유리 배경이 붙지 않는다.
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .interpolation(.none)
            .frame(width: 18, height: 18)
            .foregroundStyle(.primary)
            .accessibilityLabel("Qr2fa")
    }

    /// 목록 열의 툴바 — 계정 추가.
    ///
    /// 남은 시간 링은 두지 않는다. 링이 재촉하는 건 **지금 보고 있는 코드**인데, 그 코드는
    /// 상세 열에 있고 거기에 이미 링이 붙어 있다. 툴바에도 두면 같은 것을 두 번 말하면서
    /// 목록만 보는 동안에는 가리킬 대상이 없다.
    ///
    /// 별도 프로퍼티로 뺀 이유는 타입 체커다. `body` 안에 인라인으로 두면 표현식이 너무
    /// 커져서 "reasonable time 안에 타입 체크 불가"로 빌드가 깨진다.
    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                showingAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help("계정 추가")
            .accessibilityLabel("계정 추가")
        }
    }

    private var sidebarView: some View {
        List(selection: $selection) {
            // "모든 계정"은 서비스 하나가 아니라 **전체**다. 아래 목록과 같은 소제목 밑에
            // 두면 서비스 이름 중 하나처럼 읽힌다 — 소제목 위에 따로 둔다.
            Section {
                Text("모든 계정")
                    .tag(SidebarItem.allAccounts)
            }

            Section("계정") {
                ForEach(issuers, id: \.self) { issuer in
                    Text(issuer)
                        .tag(SidebarItem.issuer(issuer))
                }
                .onMove { source, destination in
                    moveIssuers(from: source, to: destination)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 180)
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
}

private struct AccountRowView: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(account.displayIssuer)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !account.tag.isEmpty {
                    TagBadgeView(tag: account.tag)
                }
            }
            if !account.issuer.isEmpty {
                Text(account.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
    }
}
