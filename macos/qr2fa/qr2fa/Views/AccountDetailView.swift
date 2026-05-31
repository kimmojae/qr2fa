import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct AccountDetailView: View {
    let account: Account

    @State private var totpCode: String = "------"
    @State private var remaining: Int = 30
    @State private var qrImage: NSImage?
    @State private var showCopied = false
    @State private var isHoveringTOTP = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 계정 정보 카드
                accountInfoCard

                // TOTP 카드
                totpCard

                // QR 카드
                qrCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .onAppear {
            qrImage = generateQRImage()
            refreshTOTP()
        }
        .onReceive(timer) { _ in refreshTOTP() }
    }

    // MARK: - Subviews

    private var accountInfoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("서비스")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)
            Text(account.issuer.isEmpty ? account.name : account.issuer)
                .font(.system(size: 15, weight: .semibold))

            Divider()
                .padding(.vertical, 2)

            Text("계정")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)
            Text(account.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(account.issuer.isEmpty ? .secondary : .primary)

            if !account.tag.isEmpty {
                Divider()
                    .padding(.vertical, 2)

                Text("태그")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                TagBadgeView(tag: account.tag)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: NSColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.top, 16)
    }

    private var totpCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("인증 코드")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)

                Text(showCopied ? "Copied!" : TOTPGenerator.formattedCode(totpCode))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(showCopied ? Color.green : (remaining <= 5 ? Color.orange : Color.primary))
            }

            Spacer()

            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 2.5)
                        .frame(width: 32, height: 32)
                    Circle()
                        .trim(from: 0, to: CGFloat(remaining) / CGFloat(account.period))
                        .stroke(remaining <= 5 ? Color.orange : Color.green, lineWidth: 2.5)
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                    Text("\(remaining)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(remaining <= 5 ? .orange : .primary)
                }
                Text("초")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(isHoveringTOTP
            ? Color(nsColor: NSColor(red: 0.22, green: 0.22, blue: 0.23, alpha: 1))
            : Color(nsColor: NSColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHoveringTOTP = $0 }
        .onTapGesture { copyCode() }
    }

    private var qrCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QR 코드")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            if let qrImage {
                Image(nsImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: NSColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
}
