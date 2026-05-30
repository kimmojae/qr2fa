import SwiftUI

enum AccountDetailMode: Hashable {
    case add
    case edit(Account)
}

struct AccountsSettingsView: View {
    @Environment(StorageService.self) private var storageService
    @State private var navPath = NavigationPath()

    private var grouped: [(issuer: String, accounts: [Account])] {
        var dict: [String: [Account]] = [:]
        for acc in storageService.accounts {
            let key = acc.issuer.isEmpty ? acc.name : acc.issuer
            dict[key, default: []].append(acc)
        }
        return dict.keys.sorted().map { (issuer: $0, accounts: dict[$0]!) }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if storageService.accounts.isEmpty {
                    emptyView
                } else {
                    accountList
                }
            }
            .navigationTitle("계정")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        navPath.append(AccountDetailMode.add)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: AccountDetailMode.self) { mode in
                AccountDetailView(mode: mode) {
                    navPath.removeLast()
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("계정이 없습니다")
                .foregroundStyle(.secondary)
            Button("계정 추가") {
                navPath.append(AccountDetailMode.add)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accountList: some View {
        List {
            ForEach(grouped, id: \.issuer) { group in
                Section {
                    ForEach(group.accounts) { account in
                        AccountSettingsRowView(account: account)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                navPath.append(AccountDetailMode.edit(account))
                            }
                    }
                } header: {
                    HStack(spacing: 4) {
                        Text(group.issuer)
                            .font(.system(size: 11, weight: .semibold))
                        Text("(\(group.accounts.count))")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 10))
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

struct AccountSettingsRowView: View {
    let account: Account
    @State private var code: String = "------"
    @State private var remaining: Int = 30
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.system(size: 12))
                if !account.tag.isEmpty {
                    Text(account.tag)
                        .font(.system(size: 9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(tagColor.opacity(0.15))
                        .foregroundStyle(tagColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            Spacer()
            Text(TOTPGenerator.formattedCode(code))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
            TimerDotsView(remaining: remaining, period: account.period)
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .onAppear { refresh() }
        .onReceive(timer) { _ in refresh() }
    }

    private var tagColor: Color {
        switch account.tag.lowercased() {
        case "prod": return .red
        case "dev":  return .blue
        default:     return .purple
        }
    }

    private func refresh() {
        code = (try? TOTPGenerator.generate(account: account)) ?? "------"
        remaining = TOTPGenerator.remainingSeconds(period: account.period)
    }
}
