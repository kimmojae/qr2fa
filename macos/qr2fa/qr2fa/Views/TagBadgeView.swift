import SwiftUI

struct TagBadgeView: View {
    let tag: String
    var showEditHint: Bool = false

    @Environment(TagStyle.self) private var tagStyle

    var body: some View {
        HStack(spacing: 3) {
            Text(tag.isEmpty ? "태그 추가" : tag)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if showEditHint {
                Image(systemName: "pencil")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(tag.isEmpty ? 0 : 0.16), in: Capsule())
        .overlay {
            if tag.isEmpty {
                Capsule()
                    .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
            }
        }
    }

    var color: Color { tagStyle.color }
}

