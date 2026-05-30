// macos/qr2fa/qr2fa/Views/Settings/AccountDetailView.swift
import SwiftUI
import CoreImage.CIFilterBuiltins

struct AccountDetailView: View {
    let mode: AccountDetailMode
    let onDone: () -> Void

    @Environment(StorageService.self) private var storageService
    @State private var name      = ""
    @State private var issuer    = ""
    @State private var secret    = ""
    @State private var tag       = ""
    @State private var digits    = 6
    @State private var period    = 30
    @State private var algorithm = "SHA1"
    @State private var errorMessage: String?
    @State private var showingQRCapture = false
    @State private var showDeleteAlert  = false
    @State private var code      = "------"
    @State private var remaining = 30

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingAccount: Account? {
        if case .edit(let acc) = mode { return acc }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            leftPanel
            rightPanel
        }
        .padding(24)
        .navigationTitle(isEditing ? (existingAccount?.issuer.isEmpty == false ? existingAccount!.issuer : existingAccount!.name) : "계정 추가")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { onDone() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "저장" : "추가") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || secret.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear { loadExisting(); refreshTOTP() }
        .onReceive(timer) { _ in refreshTOTP() }
        .sheet(isPresented: $showingQRCapture) {
            QRCaptureView { urlString in
                applyOTPAuthURL(urlString)
                showingQRCapture = false
            }
            .environment(storageService)
        }
        .alert("계정 삭제", isPresented: $showDeleteAlert) {
            Button("삭제", role: .destructive) { deleteAccount() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("'\(existingAccount?.name ?? "")' 계정을 삭제하시겠습니까?")
        }
    }

    // MARK: - Left panel: QR + TOTP

    private var leftPanel: some View {
        VStack(spacing: 12) {
            qrCodeView
                .frame(width: 160, height: 160)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 4) {
                Text(TOTPGenerator.formattedCode(code))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                TimerDotsView(remaining: remaining, period: period)
                Text("\(remaining)초 남음")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(width: 160)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(width: 160)
    }

    @ViewBuilder
    private var qrCodeView: some View {
        if let img = generateQRCode() {
            Image(nsImage: img)
                .resizable()
                .interpolation(.none)
        } else {
            Color.secondary.opacity(0.1)
                .overlay {
                    Text("시크릿 키를\n입력하세요")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
        }
    }

    // MARK: - Right panel: form

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("기본 정보") {
                    TextField("서비스명 (예: GitHub)", text: $issuer)
                    TextField("계정 (예: user@example.com)", text: $name)
                    HStack {
                        SecureField("시크릿 키 (Base32)", text: $secret)
                        if !isEditing {
                            Button {
                                showingQRCapture = true
                            } label: {
                                Image(systemName: "qrcode.viewfinder")
                            }
                            .help("QR 스캔")
                        }
                    }
                    TextField("태그 (예: dev, prod)", text: $tag)
                }

                DisclosureGroup("고급 설정") {
                    Picker("자릿수", selection: $digits) {
                        Text("6자리").tag(6)
                        Text("8자리").tag(8)
                    }
                    .pickerStyle(.segmented)

                    Picker("갱신 주기", selection: $period) {
                        Text("30초").tag(30)
                        Text("60초").tag(60)
                    }
                    .pickerStyle(.segmented)

                    Picker("알고리즘", selection: $algorithm) {
                        Text("SHA1").tag("SHA1")
                        Text("SHA256").tag("SHA256")
                        Text("SHA512").tag("SHA512")
                    }
                }
            }
            .formStyle(.grouped)

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            if isEditing {
                HStack {
                    Spacer()
                    Button("계정 삭제", role: .destructive) {
                        showDeleteAlert = true
                    }
                    .foregroundStyle(.red)
                }
                .padding([.horizontal, .bottom])
            }
        }
    }

    // MARK: - Helpers

    private func generateQRCode() -> NSImage? {
        let clean = secret.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "= "))
        guard !clean.isEmpty, !name.isEmpty else { return nil }

        let temp = Account(
            id: existingAccount?.id ?? 0,
            name: name, issuer: issuer, secret: clean,
            tag: tag, algorithm: algorithm, digits: digits,
            period: period, createdAt: existingAccount?.createdAt ?? Date()
        )
        let urlString = temp.toOTPAuthURL()
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(urlString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: 160, height: 160))
    }

    private func refreshTOTP() {
        let clean = secret.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "= "))
        guard !clean.isEmpty else { code = "------"; return }
        let temp = Account(
            id: 0, name: name, issuer: issuer, secret: clean,
            tag: tag, algorithm: algorithm, digits: digits,
            period: period, createdAt: Date()
        )
        code = (try? TOTPGenerator.generate(account: temp)) ?? "------"
        remaining = TOTPGenerator.remainingSeconds(period: period)
    }

    private func loadExisting() {
        guard let acc = existingAccount else { return }
        name = acc.name; issuer = acc.issuer; secret = acc.secret
        tag = acc.tag; digits = acc.digits; period = acc.period; algorithm = acc.algorithm
    }

    private func save() {
        errorMessage = nil
        let clean = secret.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "= "))
        guard (try? TOTPGenerator.generate(
            secret: clean, date: Date(), digits: digits, period: period,
            algorithm: TOTPGenerator.Algorithm.from(algorithm)
        )) != nil else {
            errorMessage = "유효하지 않은 Base32 시크릿입니다"
            return
        }
        do {
            if var acc = existingAccount {
                acc.name = name; acc.issuer = issuer; acc.secret = clean
                acc.tag = tag; acc.digits = digits; acc.period = period; acc.algorithm = algorithm
                try storageService.update(acc)
            } else {
                try storageService.add(Account(
                    id: 0, name: name, issuer: issuer, secret: clean,
                    tag: tag, algorithm: algorithm, digits: digits,
                    period: period, createdAt: Date()
                ))
            }
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAccount() {
        guard let acc = existingAccount else { return }
        try? storageService.delete(id: acc.id)
        onDone()
    }

    private func applyOTPAuthURL(_ urlString: String) {
        guard let url = URL(string: urlString),
              url.scheme == "otpauth",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let secretParam = comps.queryItems?.first(where: { $0.name == "secret" })?.value
        else { return }
        secret = secretParam
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.contains(":") {
            let parts = path.split(separator: ":", maxSplits: 1)
            issuer = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            name   = String(parts[1]).removingPercentEncoding ?? String(parts[1])
        } else {
            name = path.removingPercentEncoding ?? path
        }
        if let i = comps.queryItems?.first(where: { $0.name == "issuer" })?.value { issuer = i }
        if let d = comps.queryItems?.first(where: { $0.name == "digits" })?.value,
           let di = Int(d) { digits = di }
        if let p = comps.queryItems?.first(where: { $0.name == "period" })?.value,
           let pi = Int(p) { period = pi }
        if let a = comps.queryItems?.first(where: { $0.name == "algorithm" })?.value {
            algorithm = a.uppercased()
        }
    }
}
