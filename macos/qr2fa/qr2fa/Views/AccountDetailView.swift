import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct AccountDetailView: View {
    let account: Account
    /// 1초에 한 번 갱신되는 "지금". 예전엔 이 뷰가 자기 타이머를 돌렸는데, 목록 툴바의
    /// 링도 따로 돌고 있어서 시작 시점이 달라 둘이 1초 안쪽으로 어긋나 보였다. 시계를
    /// 하나로 모아 같은 값에서 파생시킨다.
    let now: Date
    @Binding var isEditing: Bool
    var onDelete: () -> Void = {}

    @Environment(StorageService.self) private var storageService
    @Environment(TagStyle.self) private var tagStyle
    @State private var draftName: String = ""
    @State private var draftTag: String = ""
    @State private var draftMemo: String = ""

    @State private var qrImage: NSImage?
    @State private var showCopied = false
    @State private var showSecretCopied = false
    @State private var secretRevealed = false
    @State private var qrRevealed = false
    /// QR은 접어 둔다 — 다른 기기에 등록할 때만 쓰는데, 펼쳐 두면 상세에서 가장 큰 면적을
    /// 차지한다. 게다가 그 이미지는 시크릿을 그대로 담고 있다.
    @State private var secretExpanded = false
    @State private var isHoveringCode = false

    private enum Field { case name, tag, memo }
    @FocusState private var focusedField: Field?

    /// 복사 표시가 떠 있는 시간. 메뉴바 패널(1.5초)보다 길게 둔다 — 거긴 복사하고 바로
    /// 떠나는 자리지만, 설정 창은 머무는 화면이라 금방 사라지면 본 것 같지도 않다.
    private static let copiedDuration: TimeInterval = 2.0

    /// 코드와 남은 시간은 `now` 하나에서만 파생된다 — 저장된 상태가 아니라서 툴바 링과
    /// 어긋날 수가 없다.
    private var totpCode: String {
        (try? TOTPGenerator.generate(account: account, date: now)) ?? "------"
    }

    private var remaining: Int {
        TOTPGenerator.remainingSeconds(date: now, period: account.period)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 일반 설정 페이지와 동일한 grouped Form 블록 배경(라이트/다크 자동 대응)을 쓴다.
            Form {
                // 암호 앱처럼 한 블록에 모은다. 인증 코드도 다른 줄과 같은 형태로 두되,
                // 숫자만 크게 해서 눈이 먼저 가게 한다 — 따로 카드를 주면 상세의 절반을
                // 차지하는데 그만큼의 정보량이 아니다.
                Section {
                    infoServiceRow
                    infoAccountRow
                    infoTagRow
                    totpRow
                    createdRow
                    memoRow
                }

                // 시크릿 키와 QR은 **같은 비밀의 두 형태**다(QR은 그 시크릿을 담은
                // otpauth URL을 그린 것). 평소엔 볼 일이 없고 노출되면 계정이 통째로
                // 넘어가므로 한 자리에 모아 접어 둔다.
                Section {
                    secretRow
                }
            }
            .formStyle(.grouped)
            // grouped Form은 위쪽 여백을 넉넉히 잡는데, 툴바 바로 아래라 그만큼이 빈 띠처럼
            // 보인다. `contentMargins`를 0으로 줘도 섹션 자체의 상단 여백이 남아서(29pt),
            // 그만큼을 음수 패딩으로 끌어올린다. 암호 앱은 첫 블록이 툴바에 훨씬 붙어 있다.
            .contentMargins(.top, 0, for: .scrollContent)
            // 블록의 좌우 끝을 위쪽 툴바(편집·검색)와 맞춘다. grouped Form이 자체 여백을
            // 20pt쯤 더 잡아서, 0으로 줘도 툴바보다 안쪽에 머문다 — 음수로 끌어낸다.
            .contentMargins(.horizontal, -6, for: .scrollContent)
            .padding(.top, -14)

            if isEditing {
                Divider()
                HStack {
                    Button(role: .destructive) { deleteAccount() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("계정 삭제")
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
            draftName = account.name
            draftTag = account.tag
            draftMemo = account.memo
        }
        .onChange(of: account.id) {
            draftName = account.name
            draftTag = account.tag
            draftMemo = account.memo
            qrImage = generateQRImage()
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                draftName = account.name
                draftTag = account.tag
                draftMemo = account.memo
                focusedField = .name
            } else {
                focusedField = nil
            }
        }
    }

    // MARK: - Rows (grouped Form 안의 각 행)

    private var infoServiceRow: some View {
        LabeledContent("서비스") {
            Text(account.issuer.isEmpty ? account.name : account.issuer)
                .fontWeight(.medium)
        }
    }

    private var infoAccountRow: some View {
        LabeledContent("계정") {
            if isEditing {
                TextField("계정명", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    // 편집을 누르면 여기부터 고치는 게 자연스럽다. 포커스를 주지 않으면
                    // 커서가 어디 있는지 모른 채로 시작한다.
                    .focused($focusedField, equals: .name)
            } else {
                Text(account.name)
                    .fontWeight(.medium)
                    .foregroundStyle(account.issuer.isEmpty ? .secondary : .primary)
            }
        }
    }

    private var infoTagRow: some View {
        LabeledContent("태그") {
            if isEditing {
                TextField("태그 (선택 사항)", text: $draftTag)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($focusedField, equals: .tag)
            } else if account.tag.isEmpty {
                // 비었으면 아무것도 적지 않는다. "없음"은 읽을 값이 없다는 걸 알리려고
                // 자리를 차지하는데, 줄 자체가 이미 그걸 말하고 있다.
                EmptyView()
            } else {
                // 폼의 값 자리라 메뉴바와 같은 조용한 표기를 쓴다 — 채운 알약은 "훑어야 하는"
                // 목록에서 값을 하고, 여기서는 읽기↔편집 전환이 텍스트 쪽이 더 자연스럽다.
                // 목록(AccountRowView)은 계속 TagBadgeView를 쓴다.
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.system(size: 11))
                    Text(account.tag)
                }
                .foregroundStyle(tagStyle.color)
            }
        }
    }

    /// 시크릿 키와 QR을 함께 접어 두는 블록.
    ///
    /// 셰브런을 오른쪽에 둔다 — `DisclosureGroup`은 삼각형을 라벨 왼쪽에 붙여서 다른 줄과
    /// 어긋나 보인다.
    private var secretRow: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { secretExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("시크릿 키와 QR 코드")
                    Spacer(minLength: 0)
                    // 메뉴바의 issuer 그룹과 같은 방향 표시 — 회전이 아니라 위아래로 바꾼다.
                    Image(systemName: secretExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(secretExpanded ? "시크릿 키와 QR 코드 접기" : "시크릿 키와 QR 코드 펼치기")

            if secretExpanded { secretBody }
        }
    }

    private var secretBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider().padding(.top, 10)

            LabeledContent("시크릿 키") {
                HStack(spacing: 6) {
                    Text(secretRevealed ? account.secret
                                        : String(repeating: "•", count: min(account.secret.count, 16)))
                        .font(.system(size: 12, weight: .medium,
                                      design: secretRevealed ? .monospaced : .default))
                        .foregroundStyle(showSecretCopied ? .green : (secretRevealed ? .primary : .secondary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .animation(.easeInOut(duration: 0.15), value: showSecretCopied)
                    Button {
                        secretRevealed.toggle()
                    } label: {
                        Image(systemName: secretRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(secretRevealed ? "시크릿 키 가리기" : "시크릿 키 보기")
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(account.secret, forType: .string)
                        showSecretCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedDuration) {
                            showSecretCopied = false
                        }
                    } label: {
                        Image(systemName: showSecretCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(showSecretCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("시크릿 키 복사")
                }
            }

            HStack(spacing: 8) {
                Text("QR 코드")
                Spacer(minLength: 0)
                Button { qrRevealed.toggle() } label: {
                    Image(systemName: qrRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(qrRevealed ? "QR 코드 가리기" : "QR 코드 보기")
                Button { saveQRImage() } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(qrImage == nil)
                .accessibilityLabel("QR 코드를 PNG로 저장")
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
                    .accessibilityLabel("이 계정을 다른 기기에 등록하는 QR 코드")
            }
        }
    }

    private var totpRow: some View {
        LabeledContent("인증 코드") {
            // 제스처가 아니라 버튼이어야 한다 — Form 안에서는 `onTapGesture`가 먹지 않아
            // 눌러도 복사 표시가 뜨지 않았다.
            Button(action: copyCode) {
                // 두 상태를 겹쳐 두고 투명도만 바꾼다. 내용을 갈아끼우면 블록 크기가
                // 상태마다 달라져서, 복사하는 순간 배경이 커졌다 작아진다.
                // 투명도만 바꾸면 중간에 두 글자가 반쯤 겹쳐 보여 뭉개진다. 나가는 쪽은
                // 살짝 줄어들며 사라지고 들어오는 쪽은 커지며 나타나게 해서 겹침을 감춘다.
                ZStack {
                    codeContent
                        .opacity(showCopied ? 0 : 1)
                        .scaleEffect(showCopied ? 0.92 : 1)
                        .blur(radius: showCopied ? 2 : 0)
                    copiedContent
                        .opacity(showCopied ? 1 : 0)
                        .scaleEffect(showCopied ? 1 : 0.92)
                        .blur(radius: showCopied ? 0 : 2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                // 블록의 오른쪽 여백만큼 코드가 다른 줄의 값보다 안쪽으로 들어가 있었다.
                // 레이아웃상으로만 그만큼 되돌려 값의 오른쪽 끝을 맞춘다 — 블록 자체는
                // 행의 안쪽 여백으로 살짝 넘어간다.
                .padding(.trailing, -10)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHoveringCode || showCopied ? AnyShapeStyle(.quaternary)
                                                           : AnyShapeStyle(.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .onHover { isHoveringCode = $0 }
                // 호버는 즉각적이어야 하고, 상태 전환은 스프링으로 물러야 자연스럽다.
                .animation(.easeOut(duration: 0.15), value: isHoveringCode)
                .animation(.smooth(duration: 0.32), value: showCopied)
            }
            .buttonStyle(.plain)
            .help("클릭하면 인증 코드 복사")
        }
    }

    private var codeContent: some View {
        HStack(spacing: 10) {
            CountdownRing(remaining: remaining, period: account.period)
                .frame(width: 15, height: 15)

            Text(TOTPGenerator.formattedCode(totpCode))
                // 다른 줄과 같은 크기 — 혼자 크면 줄 높이가 어긋난다.
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                // 코드가 갱신된 게 눈에 걸려야 한다. 자리별로 숫자가 굴러가며 바뀐다.
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.35), value: totpCode)
        }
    }

    private var copiedContent: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 11))
            Text("복사됨")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
    }

    private var memoRow: some View {
        LabeledContent("메모") {
            if isEditing {
                TextField("메모 (선택 사항)", text: $draftMemo, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .memo)
            } else if account.memo.isEmpty {
                EmptyView()
            } else {
                Text(account.memo)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }

    /// 계정을 언제 등록했는지. 같은 서비스에 계정이 여럿일 때 어느 게 예전 것인지 가린다.
    private var createdRow: some View {
        LabeledContent("생성일") {
            Text(account.createdAt.formatted(date: .abbreviated, time: .omitted))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func copyCode() {
        // 표시용 값이 아니라 누른 순간의 코드를 복사한다 — 틱 사이에 눌리면 한 주기
        // 지난 코드가 복사될 수 있다.
        let code = (try? TOTPGenerator.generate(account: account, date: Date())) ?? totpCode
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedDuration) {
            showCopied = false
        }
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
        updated.memo = draftMemo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { return }
        guard (try? storageService.update(updated)) != nil else { return }
        isEditing = false
    }

    private func cancelEdits() {
        draftName = account.name
        draftTag = account.tag
        draftMemo = account.memo
        isEditing = false
    }

    private func deleteAccount() {
        let alert = NSAlert()
        alert.messageText = DeleteConfirmation.title(for: account)
        alert.informativeText = DeleteConfirmation.detail(for: account)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        alert.buttons[0].hasDestructiveAction = true
        alert.buttons[1].keyEquivalent = "\u{1b}"

        let confirm: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            guard (try? storageService.delete(id: account.id)) != nil else { return }
            onDelete()
        }

        // 이 창에 속한 계정을 지우는 확인이므로 창에 붙인다. `runModal()`은 창이 아니라
        // 화면 기준으로 위치를 잡아서, 설정 창과 무관한 자리에 뜬 것처럼 보였다.
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: confirm)
        } else {
            confirm(alert.runModal())
        }
    }
}

/// 삭제 확인 문구. 같은 서비스에 계정이 여러 개면 서비스 이름만으로는 무엇이 지워지는지
/// 알 수 없으므로, Finder처럼 고유한 이름을 제목에 두고 나머지는 본문에 붙인다.
enum DeleteConfirmation {
    static func title(for account: Account) -> String {
        "'\(account.name.isEmpty ? account.displayIssuer : account.name)' 계정을 삭제할까요?"
    }

    static func detail(for account: Account) -> String {
        var identity: [String] = []
        if !account.issuer.isEmpty { identity.append(account.issuer) }
        if !account.tag.isEmpty { identity.append("태그 \(account.tag)") }

        // 시크릿은 복구할 수 없다 — "되돌릴 수 없습니다"만으로는 그 대가가 전해지지 않는다.
        let warning = "되돌릴 수 없습니다. 이 계정의 인증 코드를 다시 쓰려면 QR을 새로 등록해야 합니다."
        guard !identity.isEmpty else { return warning }
        return identity.joined(separator: " · ") + "\n\n" + warning
    }
}
