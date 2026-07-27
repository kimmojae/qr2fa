import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct AccountDetailView: View {
    let account: Account
    @Binding var isEditing: Bool
    var onDelete: () -> Void = {}

    @Environment(StorageService.self) private var storageService
    @State private var draftName: String = ""
    @State private var draftTag: String = ""

    @State private var totpCode: String = "------"
    @State private var remaining: Int = 30
    @State private var qrImage: NSImage?
    @State private var showCopied = false
    @State private var showSecretCopied = false
    @State private var secretRevealed = false
    @State private var qrRevealed = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // 일반 설정 페이지와 동일한 grouped Form 블록 배경(라이트/다크 자동 대응)을 쓴다.
            Form {
                Section {
                    infoServiceRow
                    infoAccountRow
                    if isEditing || !account.tag.isEmpty {
                        infoTagRow
                    }
                    infoSecretRow
                }

                Section {
                    totpRow
                }

                Section {
                    qrRow
                }
            }
            .formStyle(.grouped)

            if isEditing {
                Divider()
                HStack {
                    Button(role: .destructive) { deleteAccount() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    Button("취소") { cancelEdits() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.escape, modifiers: [])
                    Spacer()
                    Button("저장") { saveEdits() }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .onAppear {
            qrImage = generateQRImage()
            refreshTOTP()
            draftName = account.name
            draftTag = account.tag
        }
        .onReceive(timer) { _ in refreshTOTP() }
        .onChange(of: account.id) {
            draftName = account.name
            draftTag = account.tag
            qrImage = generateQRImage()
            refreshTOTP()
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                draftName = account.name
                draftTag = account.tag
            }
        }
    }

    // MARK: - Rows (grouped Form 안의 각 행)

    private var infoServiceRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("서비스")
            Text(account.issuer.isEmpty ? account.name : account.issuer)
                .font(.system(size: 15, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoAccountRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("계정")
            if isEditing {
                TextField("계정명", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .font(.system(size: 14, weight: .medium))
            } else {
                Text(account.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(account.issuer.isEmpty ? .secondary : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoTagRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("태그")
            if isEditing {
                TextField("태그 (선택 사항)", text: $draftTag)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .font(.system(size: 14, weight: .medium))
            } else {
                TagBadgeView(tag: account.tag)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoSecretRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("시크릿 키")
            HStack(spacing: 6) {
                Text(secretRevealed ? account.secret : String(repeating: "•", count: min(account.secret.count, 24)))
                    .font(.system(size: 13, weight: .medium, design: secretRevealed ? .monospaced : .default))
                    .foregroundStyle(showSecretCopied ? .green : (secretRevealed ? .primary : .secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .animation(.easeInOut(duration: 0.15), value: showSecretCopied)
                Spacer()
                Button {
                    secretRevealed.toggle()
                } label: {
                    Image(systemName: secretRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(account.secret, forType: .string)
                    showSecretCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSecretCopied = false }
                } label: {
                    Image(systemName: showSecretCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(showSecretCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totpRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("인증 코드")

                Text(showCopied ? "Copied!" : TOTPGenerator.formattedCode(totpCode))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(showCopied ? Color.green : (remaining <= 5 ? Color.orange : Color.primary))
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2.5)
                    .frame(width: 34, height: 34)
                Circle()
                    .trim(from: 0, to: CGFloat(remaining) / CGFloat(account.period))
                    .stroke(remaining <= 5 ? Color.orange : Color.teal, lineWidth: 2.5)
                    .frame(width: 34, height: 34)
                    .rotationEffect(.degrees(-90))
                Text("\(remaining)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(remaining <= 5 ? .orange : .teal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { copyCode() }
        .help("탭하면 인증 코드 복사")
    }

    private var qrRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("QR 코드")
                Spacer()
                Button { qrRevealed.toggle() } label: {
                    Image(systemName: qrRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Button { saveQRImage() } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(qrImage == nil)
            }

            if let qrImage {
                Image(nsImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 130, height: 130)
                    .padding(8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .blur(radius: qrRevealed ? 0 : 12)
                    .animation(.easeInOut(duration: 0.2), value: qrRevealed)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(totpCode, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }

    private func refreshTOTP() {
        totpCode = (try? TOTPGenerator.generate(account: account)) ?? "------"
        remaining = TOTPGenerator.remainingSeconds(period: account.period)
    }

    private func saveQRImage() {
        guard let image = qrImage else { return }
        let panel = NSSavePanel()
        let filename = account.issuer.isEmpty ? account.name : "\(account.issuer)-\(account.name)"
        panel.nameFieldStringValue = "\(filename)-qr.png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    private func generateQRImage() -> NSImage? {
        guard let data = account.toOTPAuthURL().data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let ciImage = filter.outputImage else { return nil }
        let scale = 300.0 / ciImage.extent.width
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private func saveEdits() {
        var updated = account
        updated.name = draftName.trimmingCharacters(in: .whitespaces)
        updated.tag = draftTag.trimmingCharacters(in: .whitespaces)
        guard !updated.name.isEmpty else { return }
        guard (try? storageService.update(updated)) != nil else { return }
        isEditing = false
    }

    private func cancelEdits() {
        draftName = account.name
        draftTag = account.tag
        isEditing = false
    }

    private func deleteAccount() {
        let alert = NSAlert()
        let displayName = account.issuer.isEmpty ? account.name : account.issuer
        alert.messageText = "\(displayName) 계정을 삭제할까요?"
        alert.informativeText = "되돌릴 수 없습니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard (try? storageService.delete(id: account.id)) != nil else { return }
        onDelete()
    }
}

/// 카드 안에서 반복되는 섹션 제목 라벨(작은 대문자 회색).
private func sectionLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .kerning(0.5)
}
