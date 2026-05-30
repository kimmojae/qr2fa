import SwiftUI

struct AccountGroupView: View {
    let tag: String
    let accounts: [Account]
    let onEdit: (Account) -> Void
    @State private var isExpanded = true

    var body: some View {
        Section {
            if isExpanded {
                ForEach(accounts) { account in
                    AccountRowView(account: account, onEdit: onEdit)
                    if account.id != accounts.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(tag.isEmpty ? "태그 없음" : tag)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
