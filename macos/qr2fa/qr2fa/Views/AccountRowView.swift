import SwiftUI

struct AccountRowView: View {
    let account: Account
    let onEdit: (Account) -> Void
    @Environment(StorageService.self) private var storageService
    @State private var code: String = "------"
    @State private var remaining: Int = 30
    @State private var showCopied = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            // Left: issuer + name
            VStack(alignment: .leading, spacing: 2) {
                Text(account.issuer.isEmpty ? account.name : account.issuer)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !account.issuer.isEmpty {
                    Text(account.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: code + timer
            VStack(alignment: .trailing, spacing: 3) {
                Text(displayCode)
                    .font(.system(size: 14, design: .monospaced).weight(.semibold))
                    .foregroundStyle(showCopied ? Color.green : Color.primary)
                    .animation(.easeInOut(duration: 0.2), value: showCopied)

                TimerDotsView(remaining: remaining, period: account.period)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { copyCode() }
        .onReceive(timer) { _ in refresh() }
        .onAppear { refresh() }
        .contextMenu {
            Button("편집") { onEdit(account) }
            Divider()
            Button("삭제", role: .destructive) {
                try? storageService.delete(id: account.id)
            }
        }
    }

    private var displayCode: String {
        showCopied ? "복사됨!" : TOTPGenerator.formattedCode(code)
    }

    private func refresh() {
        code = (try? TOTPGenerator.generate(account: account)) ?? "------"
        remaining = TOTPGenerator.remainingSeconds(period: account.period)
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopied = false
        }
    }
}

struct TimerDotsView: View {
    let remaining: Int
    let period: Int
    private let totalDots = 5

    private var filledDots: Int {
        Int(ceil(Double(remaining) / Double(period) * Double(totalDots)))
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<totalDots, id: \.self) { i in
                Circle()
                    .fill(i < filledDots ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
    }
}
