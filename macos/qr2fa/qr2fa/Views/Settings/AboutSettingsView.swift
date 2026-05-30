import SwiftUI

struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.viewfinder")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("qr2fa")
                    .font(.title2.bold())
                Text("버전 \(version) (\(build))")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
