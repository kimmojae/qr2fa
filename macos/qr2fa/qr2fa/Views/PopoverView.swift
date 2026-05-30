import SwiftUI

struct PopoverView: View {
    @Environment(StorageService.self) private var storageService
    @State private var searchText = ""

    private var groupedAccounts: [(tag: String, accounts: [Account])] {
        let source = storageService.accounts
        let filtered = searchText.isEmpty ? source : source.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.issuer.localizedCaseInsensitiveContains(searchText)
        }
        var dict: [String: [Account]] = [:]
        for acc in filtered { dict[acc.tag, default: []].append(acc) }
        return dict.keys.sorted { a, b in
            if a.isEmpty { return false }
            if b.isEmpty { return true }
            return a < b
        }.map { (tag: $0, accounts: dict[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 11))
                TextField("검색", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                Spacer()
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("계정 추가")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            if storageService.accounts.isEmpty && searchText.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "key.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("계정이 없습니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("추가") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groupedAccounts.isEmpty {
                Text("'\(searchText)' 없음")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(groupedAccounts, id: \.tag) { group in
                            AccountGroupView(tag: group.tag, accounts: group.accounts)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(width: 300, height: 380)
    }
}
