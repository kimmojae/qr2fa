import SwiftUI

extension Account {
    var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo]
        return colors[stableColorIndex(for: issuer + name, count: colors.count)]
    }

    var avatarInitial: String {
        String((issuer.isEmpty ? name : issuer).prefix(1)).uppercased()
    }

    private func stableColorIndex(for string: String, count: Int) -> Int {
        let hash = string.unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) }
        return abs(hash) % count
    }
}
