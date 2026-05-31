import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct AccountDetailView: View {
    let account: Account

    @State private var totpCode: String = "------"
    @State private var remaining: Int = 30

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 아바타 + 이름
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(account.avatarColor.opacity(0.25))
                            .frame(width: 80, height: 80)
                        Text(account.avatarInitial)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(account.avatarColor)
                    }

                    Text(account.name)
                        .font(.system(size: 19, weight: .bold))
                        .multilineTextAlignment(.center)

                    if !account.issuer.isEmpty {
                        Text(account.issuer)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 24)

                // TOTP 카드
                totpCard

                // QR 카드
                qrCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .onAppear { refreshTOTP() }
        .onReceive(timer) { _ in refreshTOTP() }
    }

    // MARK: - Subviews

    private var totpCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("인증 코드")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)

                Text(TOTPGenerator.formattedCode(totpCode))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(remaining <= 5 ? Color.orange : Color.green)
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
        .background(Color(nsColor: NSColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var qrCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QR 코드")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            if let qrImage = generateQRImage() {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
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
