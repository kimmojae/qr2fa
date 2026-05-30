import SwiftUI

struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case accounts = "계정"
        case general  = "일반"
        case about    = "정보"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .accounts: return "person.2"
            case .general:  return "gear"
            case .about:    return "info.circle"
            }
        }
    }

    @State private var selectedTab: Tab = .accounts

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("qr2fa")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 20)

                ForEach(Tab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 10)
                            .background(selectedTab == tab ? Color.accentColor : Color.clear)
                            .foregroundStyle(selectedTab == tab ? .white : .secondary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                }

                Spacer()
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch selectedTab {
            case .accounts: Text("계정 준비 중")
            case .general:  GeneralSettingsView()
            case .about:    AboutSettingsView()
            }
        }
        .frame(minWidth: 700, idealWidth: 720, minHeight: 460, idealHeight: 500)
    }
}
