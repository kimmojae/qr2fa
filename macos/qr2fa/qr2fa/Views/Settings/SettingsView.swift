import SwiftUI

struct SettingsView: View {
    @Environment(StorageService.self) private var storageService
    @State private var selectedIssuer: String? = nil
    @State private var selectedAccountID: Int? = nil
    @State private var showingAddSheet = false
    @State private var showingEditSheet = false

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

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedIssuer) {
                Text("모든 계정")
                    .tag("__all__")

                if !issuers.isEmpty {
                    Section("서비스") {
                        ForEach(issuers, id: \.self) { issuer in
                            Label(issuer, systemImage: "lock.shield")
                                .tag(issuer)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            .onAppear { selectedIssuer = "__all__" }
        } content: {
            List(selection: $selectedAccountID) {
                ForEach(listedAccounts) { account in
                    AccountRowView(account: account)
                        .tag(account.id)
                }
            }
            .listStyle(.inset)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let account = selectedAccount {
                AccountDetailView(account: account)
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
                Button {
                    showingEditSheet = true
                } label: {
                    Text("편집")
                }
                .buttonStyle(.bordered)
                .disabled(true)
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
        .sheet(isPresented: $showingAddSheet) {
            AccountAddSheet(prefilledIssuer: nil).environment(storageService)
        }
    }
}

private struct AccountRowView: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(account.avatarColor.opacity(0.3))
                    .frame(width: 40, height: 40)
                Text(account.avatarInitial)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(account.avatarColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !account.issuer.isEmpty {
                    Text(account.issuer)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }
}
