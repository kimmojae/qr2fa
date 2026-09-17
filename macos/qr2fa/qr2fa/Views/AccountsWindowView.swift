import SwiftUI

/// The two sidebar rows that are not services.
enum SettingsSelection {
    static let allAccounts = "__all__"
    static let general = "__general__"
}

/// Where the sidebar should land right after accounts were added.
enum AddedAccountFocus {
    /// The service tab that shows *all* of `added`, or `nil` when nothing was added.
    /// A mixed import has no such tab, so it falls back to 모든 계정 — sending it to
    /// one service would hide the rest of what the user just imported.
    static func issuer(for added: [Account]) -> String? {
        guard let first = added.first else { return nil }
        let issuers = Set(added.map(\.displayIssuer))
        return issuers.count == 1 ? first.displayIssuer : SettingsSelection.allAccounts
    }
}

struct SettingsView: View {
    @Environment(StorageService.self) private var storageService
    @State private var selectedIssuer: String? = SettingsSelection.allAccounts
    @State private var selectedAccountID: Int? = nil
    @State private var showingAddSheet = false
    @State private var isEditingAccount: Bool = false
    @State private var scrollTarget: Int?

    private var issuers: [String] {
        AccountOrdering.issuers(in: storageService.accounts)
    }

    private var listedAccounts: [Account] {
        guard let issuer = selectedIssuer, issuer != SettingsSelection.allAccounts else {
            return storageService.accounts
        }
        return storageService.accounts.filter { $0.displayIssuer == issuer }
    }

    private var selectedAccount: Account? {
        guard let id = selectedAccountID else { return nil }
        return storageService.accounts.first { $0.id == id }
    }

    private var isGeneralSelected: Bool {
        selectedIssuer == SettingsSelection.general
    }

    // 사이드바에서 선택한 항목의 이름 — 둘째 열(계정 목록) 상단 제목으로 쓴다.
    private var contentTitle: String {
        guard let issuer = selectedIssuer, issuer != SettingsSelection.allAccounts else {
            return "모든 계정"
        }
        return issuer
    }

    var body: some View {
        // Group으로 감싸서 .onAppear/.onDisappear를 여기 붙인다 — Group 자체는 내부 if/else가
        // 바뀌어도 정체성이 유지되므로, 일반⇄계정 토글마다가 아니라 창이 실제로 열리고 닫힐 때만 실행된다.
        Group {
            if isGeneralSelected {
                NavigationSplitView {
                    sidebarView
                } detail: {
                    GeneralSettingsView()
                        .environment(storageService)
                }
                .navigationTitle("")
            } else {
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
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240)
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
                } detail: {
                    if let account = selectedAccount {
                        AccountDetailView(account: account, isEditing: $isEditingAccount) {
                            selectedAccountID = nil
                            isEditingAccount = false
                        }
                        .environment(storageService)
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
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if isEditingAccount {
                            Button("편집 취소") {
                                isEditingAccount = false
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                isEditingAccount = true
                            } label: {
                                Text("편집")
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedAccount == nil)
                            .help("계정 편집")

                            Button {
                                showingAddSheet = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.bordered)
                            .help("계정 추가")
                        }
                    }
                }
                .sheet(isPresented: $showingAddSheet) {
                    AccountAddSheet { added in
                        focus(on: added)
                    }
                    .environment(storageService)
                }
            }
        }
        .onAppear {
            if selectedAccountID == nil {
                selectedAccountID = listedAccounts.first?.id
            }
        }
        .onDisappear {
            // 창을 닫을 때 상태를 초기화해서, 다음에 열 때는 항상 "모든 계정"에서 시작하게 한다.
            selectedIssuer = SettingsSelection.allAccounts
            selectedAccountID = nil
            isEditingAccount = false
        }
        .onChange(of: issuers) {
            // 서비스 목록은 계정에서 파생된다 — 마지막 계정이 사라지면(삭제, CLI 쪽 편집,
            // issuer 이름 변경) 그 서비스는 사이드바에서 없어지는데, selectedIssuer는
            // 사라진 이름을 그대로 붙들고 있어 "빈 서비스"가 선택된 것처럼 보인다.
            // 그런 상태가 되면 "모든 계정"으로 되돌린다.
            guard let issuer = selectedIssuer,
                  issuer != SettingsSelection.allAccounts, issuer != SettingsSelection.general,
                  !issuers.contains(issuer) else { return }
            selectedIssuer = SettingsSelection.allAccounts
        }
        .onChange(of: selectedIssuer) {
            // sidebarView 안이 아니라 여기(Group)에 붙인다 — sidebarView는 일반⇄계정 전환마다
            // 다시 마운트되는 인스턴스라, 전환을 유발한 바로 그 선택 변경에 대해서는 onChange가
            // 발동하지 않을 수 있다. Group은 정체성이 유지되므로 모든 전환에서 안정적으로 발동한다.
            guard !isGeneralSelected else { return }
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
    private var selectedService: String? {
        guard let issuer = selectedIssuer,
              issuer != SettingsSelection.allAccounts,
              issuer != SettingsSelection.general else { return nil }
        return issuer
    }

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
        guard let issuer = AddedAccountFocus.issuer(for: added),
              let first = added.first else { return }
        isEditingAccount = false
        selectedAccountID = first.id
        selectedIssuer = issuer
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

    private var sidebarView: some View {
        List(selection: $selectedIssuer) {
            Section {
                Text("일반")
                    .tag(SettingsSelection.general)
            }

            Section("계정") {
                Text("모든 계정")
                    .tag(SettingsSelection.allAccounts)

                ForEach(issuers, id: \.self) { issuer in
                    Text(issuer)
                        .tag(issuer)
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
