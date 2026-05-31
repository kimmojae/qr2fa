import SwiftUI

struct AccountAddSheet: View {
    let prefilledIssuer: String?
    @Environment(StorageService.self) private var storageService
    @Environment(\.dismiss) private var dismiss

    enum Tab { case qr, manual }
    @State private var tab: Tab = .qr
    @State private var showingQRCapture = false

    // Single-account QR state
    @State private var parsedAccount: Account?
    @State private var showSingleConfirm = false

    // Migration state
    @State private var migrationAccounts: [MigrationEntry] = []

    // Manual form
    @State private var issuer = ""
    @State private var name = ""
    @State private var secret = ""
    @State private var tag = ""
    @State private var showTagPopover = false

    // Shared
    @State private var errorMessage: String?
    @State private var pastedURL = ""

    struct MigrationEntry: Identifiable {
        let id = UUID()
        var account: Account
        var tag: String = ""
        var skip: Bool = false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("계정 추가").font(.headline)
                Spacer()
                Picker("", selection: $tab) {
                    Text("QR 스캔").tag(Tab.qr)
                    Text("직접 입력").tag(Tab.manual)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Body
            ScrollView {
                Group {
                    switch tab {
                    case .qr:   qrPane
                    case .manual: manualPane
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                if let err = errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button(tab == .qr && !migrationAccounts.isEmpty ? "일괄 추가" : "추가") {
                    addAccounts()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 460)
        .sheet(isPresented: $showingQRCapture) {
            QRCaptureView { urlString in
                handleCapturedURL(urlString)
                showingQRCapture = false
            }
            .environment(storageService)
        }
        .onAppear {
            if let issuer = prefilledIssuer { self.issuer = issuer }
        }
    }

    // MARK: - QR Pane

    private var qrPane: some View {
        VStack(spacing: 16) {
            // Scan button
            Button {
                parsedAccount = nil
                migrationAccounts = []
                errorMessage = nil
                showingQRCapture = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("화면에서 QR 캡처")
                        .font(.system(size: 13, weight: .medium))
                    Text("클릭하면 화면 선택 모드 진입")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color.accentColor.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5])))
            }
            .buttonStyle(.plain)

            // Migration preview
            if !migrationAccounts.isEmpty {
                migrationPreview
            }

            // Single QR confirmation
            if let acc = parsedAccount, migrationAccounts.isEmpty {
                singleAccountConfirm(acc)
            }

            // URL paste
            HStack { Divider(); Text("또는").font(.caption).foregroundStyle(.secondary); Divider() }

            VStack(alignment: .leading, spacing: 4) {
                Text("otpauth:// URL 직접 붙여넣기")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("otpauth://totp/...", text: $pastedURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    Button("파싱") {
                        handleCapturedURL(pastedURL)
                    }
                    .disabled(pastedURL.isEmpty)
                }
            }
        }
    }

    private var migrationPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 11))
                Text("Google Authenticator 내보내기 감지 — \(migrationAccounts.filter { !$0.skip }.count)개 추가 예정")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ForEach($migrationAccounts) { $entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.skip ? "minus.circle" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(entry.skip ? .secondary : .primary)
                        .onTapGesture { entry.skip.toggle() }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.account.issuer.isEmpty ? entry.account.name : "\(entry.account.issuer) · \(entry.account.name)")
                            .font(.system(size: 11))
                            .foregroundStyle(entry.skip ? .secondary : .primary)
                        if entry.skip {
                            Text("건너뜀").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !entry.skip {
                        Picker("", selection: $entry.tag) {
                            Text("태그 없음").tag("")
                            Text("prod").tag("prod")
                            Text("dev").tag("dev")
                            Text("staging").tag("staging")
                        }
                        .labelsHidden()
                        .font(.system(size: 11))
                        .frame(width: 100)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func singleAccountConfirm(_ acc: Account) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 11))
                Text("QR 인식 완료")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("서비스명").font(.system(size: 10)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(acc.issuer.isEmpty ? "(없음)" : acc.issuer).font(.system(size: 12))
                }
                GridRow {
                    Text("계정").font(.system(size: 10)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(acc.name).font(.system(size: 12))
                }
                GridRow {
                    Text("태그").font(.system(size: 10)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    HStack {
                        TagBadgeView(tag: tag, showEditHint: true)
                            .onTapGesture { showTagPopover = true }
                            .popover(isPresented: $showTagPopover, arrowEdge: .bottom) {
                                TagSelectorPopover(tag: $tag)
                            }
                        Spacer()
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Manual Pane

    private var manualPane: some View {
        VStack(spacing: 12) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    fieldLabel("서비스명")
                    TextField("예: GitHub", text: $issuer)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    fieldLabel("계정")
                    TextField("예: user@example.com", text: $name)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                }
                GridRow {
                    fieldLabel("시크릿 키")
                    TextField("Base32 (예: JBSWY3DP...)", text: $secret)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                        .gridCellColumns(3)
                }
                GridRow {
                    fieldLabel("태그")
                    HStack {
                        TagBadgeView(tag: tag, showEditHint: true)
                            .onTapGesture { showTagPopover = true }
                            .popover(isPresented: $showTagPopover, arrowEdge: .bottom) {
                                TagSelectorPopover(tag: $tag)
                            }
                        Spacer()
                    }
                    .gridCellColumns(3)
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    // MARK: - Logic

    private var canAdd: Bool {
        switch tab {
        case .qr:
            return !migrationAccounts.filter({ !$0.skip }).isEmpty || parsedAccount != nil
        case .manual:
            return !name.isEmpty && !secret.isEmpty
        }
    }

    private func handleCapturedURL(_ urlString: String) {
        errorMessage = nil
        parsedAccount = nil
        migrationAccounts = []

        if urlString.hasPrefix("otpauth-migration://") {
            let accounts = MigrationParser.parse(url: urlString) ?? []
            migrationAccounts = accounts.map { acc in
                var entry = MigrationEntry(account: acc)
                if let existing = storageService.accounts.first(where: {
                    $0.secret.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "=")) ==
                    acc.secret.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "="))
                }) {
                    _ = existing
                    entry.skip = true
                }
                return entry
            }
            if migrationAccounts.isEmpty {
                errorMessage = "계정을 파싱할 수 없습니다"
            }
        } else if urlString.hasPrefix("otpauth://totp/") {
            guard let acc = parseOTPAuthURL(urlString) else {
                errorMessage = "QR 코드를 파싱할 수 없습니다"
                return
            }
            parsedAccount = acc
            tag = acc.tag
        }
    }

    private func addAccounts() {
        errorMessage = nil
        do {
            switch tab {
            case .qr:
                if !migrationAccounts.isEmpty {
                    for entry in migrationAccounts where !entry.skip {
                        var acc = entry.account
                        acc.tag = entry.tag
                        try storageService.add(acc)
                    }
                } else if var acc = parsedAccount {
                    acc.tag = tag
                    try storageService.add(acc)
                }
            case .manual:
                let clean = secret.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "= "))
                let acc = Account(
                    id: 0, name: name, issuer: issuer, secret: clean,
                    tag: tag, algorithm: "SHA1", digits: 6, period: 30, createdAt: Date()
                )
                try storageService.add(acc)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseOTPAuthURL(_ urlString: String) -> Account? {
        guard let url = URL(string: urlString),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let secretParam = comps.queryItems?.first(where: { $0.name == "secret" })?.value
        else { return nil }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var issuer = "", name = path.removingPercentEncoding ?? path
        if path.contains(":") {
            let parts = path.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                issuer = (String(parts[0]).removingPercentEncoding ?? String(parts[0]))
                name = (String(parts[1]).removingPercentEncoding ?? String(parts[1]))
            }
        }
        if let qi = comps.queryItems?.first(where: { $0.name == "issuer" })?.value { issuer = qi }

        let digits = comps.queryItems?.first(where: { $0.name == "digits" }).flatMap { Int($0.value ?? "") } ?? 6
        let period = comps.queryItems?.first(where: { $0.name == "period" }).flatMap { Int($0.value ?? "") } ?? 30
        let algorithm = comps.queryItems?.first(where: { $0.name == "algorithm" })?.value?.uppercased() ?? "SHA1"

        let clean = secretParam.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "= "))
        return Account(id: 0, name: name, issuer: issuer, secret: clean, tag: "",
                       algorithm: algorithm, digits: digits, period: period, createdAt: Date())
    }
}
