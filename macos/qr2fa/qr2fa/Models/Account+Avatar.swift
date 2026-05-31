import SwiftUI

extension Account {
    var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo]
        let idx = abs((issuer + name).hashValue) % colors.count
        return colors[idx]
    }

    var avatarInitial: String {
        String((issuer.isEmpty ? name : issuer).prefix(1)).uppercased()
    }
}
