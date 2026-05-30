import SwiftUI

struct PopoverView: View {
    @Environment(StorageService.self) private var storageService
    @State private var searchText = ""
    @State private var showingAddAccount = false
    @State private var accountToEdit: Account?

    private var groupedAccounts: [(tag: String, accounts: [Account])] {
        let source = storageService.accounts
        let filtered = searchText.isEmpty ? source : source.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.issuer.localizedCaseInsensitiveContains(searchText)
        }

        var dict: [String: [Account]] = [:]
        for acc in filtered {
            dict[acc.tag, default: []].append(acc)
        }
        // Sort: named tags alphabetically first, empty tag ("태그 없음") last
        return dict.keys.sorted { a, b in
            if a.isEmpty { return false }
            if b.isEmpty { return true }
            return a < b
        }.map { (tag: $0, accounts: dict[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search + add bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField("검색...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                Spacer()
                Button {
                    showingAddAccount = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("계정 추가")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if storageService.accounts.isEmpty && searchText.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "key.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("계정이 없습니다")
                        .foregroundStyle(.secondary)
                    Button("계정 추가") { showingAddAccount = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if groupedAccounts.isEmpty {
                // No search results
                Text("'\(searchText)'에 해당하는 계정 없음")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(groupedAccounts, id: \.tag) { group in
                            AccountGroupView(
                                tag: group.tag,
                                accounts: group.accounts,
                                onEdit: { account in accountToEdit = account }
                            )
                        }
                    }
                }
            }
        }
        .frame(width: 320, height: 420)
        .sheet(isPresented: $showingAddAccount) {
            AddEditAccountView(mode: .add)
                .environment(storageService)
        }
        .sheet(item: $accountToEdit) { account in
            AddEditAccountView(mode: .edit(account))
                .environment(storageService)
        }
    }
}
