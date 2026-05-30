import SwiftUI

struct AddEditAccountView: View {
    enum Mode {
        case add
        case edit(Account)
    }

    let mode: Mode
    @Environment(StorageService.self) private var storageService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var issuer = ""
    @State private var secret = ""
    @State private var tag = ""
    @State private var digits = 6
    @State private var period = 30
    @State private var algorithm = "SHA1"
    @State private var errorMessage: String?
    @State private var showingQRCapture = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingAccount: Account? {
        if case .edit(let acc) = mode { return acc }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(isEditing ? "계정 편집" : "계정 추가")
                    .font(.headline)
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

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
                            .help("QR 코드 스캔")
                        }
                    }
                    TextField("태그 (예: dev, prod)", text: $tag)
                }

                Section("고급 설정") {
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

            Divider()

            HStack {
                Spacer()
                Button(isEditing ? "저장" : "추가") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || secret.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(width: 380, height: 480)
        .onAppear { loadExisting() }
        .sheet(isPresented: $showingQRCapture) {
            QRCaptureView { urlString in
                applyOTPAuthURL(urlString)
                showingQRCapture = false
            }
            .environment(storageService)
        }
    }

    // MARK: - Private

    private func loadExisting() {
        guard let acc = existingAccount else { return }
        name = acc.name
        issuer = acc.issuer
        secret = acc.secret
        tag = acc.tag
        digits = acc.digits
        period = acc.period
        algorithm = acc.algorithm
    }

    private func save() {
        errorMessage = nil
        let cleanSecret = secret.uppercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "= "))

        // Validate by attempting TOTP generate
        guard (try? TOTPGenerator.generate(
            secret: cleanSecret, date: Date(), digits: digits, period: period,
            algorithm: TOTPGenerator.Algorithm.from(algorithm)
        )) != nil else {
            errorMessage = "유효하지 않은 Base32 시크릿입니다"
            return
        }

        do {
            if var acc = existingAccount {
                acc.name      = name
                acc.issuer    = issuer
                acc.secret    = cleanSecret
                acc.tag       = tag
                acc.digits    = digits
                acc.period    = period
                acc.algorithm = algorithm
                try storageService.update(acc)
            } else {
                let acc = Account(
                    id: 0, name: name, issuer: issuer, secret: cleanSecret,
                    tag: tag, algorithm: algorithm, digits: digits, period: period,
                    createdAt: Date()
                )
                try storageService.add(acc)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyOTPAuthURL(_ urlString: String) {
        guard let url = URL(string: urlString),
              url.scheme == "otpauth",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let secretParam = components.queryItems?.first(where: { $0.name == "secret" })?.value
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

        if let issuerParam = components.queryItems?.first(where: { $0.name == "issuer" })?.value {
            issuer = issuerParam
        }
        if let d = components.queryItems?.first(where: { $0.name == "digits" })?.value,
           let di = Int(d) { digits = di }
        if let p = components.queryItems?.first(where: { $0.name == "period" })?.value,
           let pi = Int(p) { period = pi }
        if let alg = components.queryItems?.first(where: { $0.name == "algorithm" })?.value {
            algorithm = alg.uppercased()
        }
    }
}
