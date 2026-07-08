import SwiftUI

struct SettingsView: View {
    @Environment(StorageService.self) private var storageService
    @State private var selectedIssuer: String? = nil
    @State private var selectedAccountID: Int? = nil
    @State private var showingAddSheet = false
    @State private var isEditingAccount: Bool = false

    private var issuers: [String] {
        let all = storageService.accounts.map { $0.issuer.isEmpty ? $0.name : $0.issuer }
        return Array(Set(all)).sorted()
    }

    private var listedAccounts: [Account] {
        guard let issuer = selectedIssuer, issuer != "__all__" else {
            return storageService.accounts
        }
        return storageService.accounts.filter {
            ($0.issuer.isEmpty ? $0.name : $0.issuer) == issuer
        }
    }

    private var selectedAccount: Account? {
        guard let id = selectedAccountID else { return nil }
        return storageService.accounts.first { $0.id == id }
    }

    private var isGeneralSelected: Bool {
        selectedIssuer == "__general__"
    }

    var body: some View {
        if isGeneralSelected {
            NavigationSplitView {
                sidebarView
            } detail: {
                GeneralSettingsView()
                    .environment(storageService)
            }
        } else {
            NavigationSplitView {
                sidebarView
            } content: {
                List(selection: $selectedAccountID) {
                    ForEach(listedAccounts) { account in
                        AccountRowView(account: account)
                            .tag(account.id)
                    }
                }
                .listStyle(.inset)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                .onChange(of: selectedAccountID) {
                    isEditingAccount = false
                }
            } detail: {
                if let account = selectedAccount {
                    AccountDetailView(account: account, isEditing: $isEditingAccount) {
                        selectedAccountID = nil
                        isEditingAccount = false
                    }
                    .environment(storageService)
                } else {
                    ContentUnavailableView(
                        "계정을 선택하세요",
                        systemImage: "qrcode",
                        description: Text("왼쪽 목록에서 계정을 선택하면 QR 코드와 인증 코드를 볼 수 있습니다.")
                    )
                }
            }
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
                AccountAddSheet().environment(storageService)
            }
        }
    }

    private var sidebarView: some View {
        List(selection: $selectedIssuer) {
            Section {
                Text("일반")
                    .tag("__general__")
            }

            Text("모든 계정")
                .tag("__all__")

            if !issuers.isEmpty {
                Section("서비스") {
                    ForEach(issuers, id: \.self) { issuer in
                        Text(issuer)
                            .tag(issuer)
                    }
                }
            }
        }
        .onAppear {
            // 모드 전환으로 사이드바가 다시 마운트될 때 "__general__" 선택을 덮어쓰지 않도록 가드.
            if selectedIssuer == nil {
                selectedIssuer = "__all__"
            }
        }
        .onChange(of: selectedIssuer) {
            guard !isGeneralSelected else { return }
            // 서비스 그룹을 바꾸면 편집 상태를 끄고 그 그룹의 첫 번째 계정을 선택한다.
            isEditingAccount = false
            selectedAccountID = listedAccounts.first?.id
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 180)
    }
}

private struct AccountRowView: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(account.issuer.isEmpty ? account.name : account.issuer)
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
