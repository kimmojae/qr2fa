import SwiftUI

struct TagBadgeView: View {
    let tag: String
    var showEditHint: Bool = false

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

    // 프리셋/색 매핑을 없앴으므로 모든 태그는 단일 색으로 통일한다.
    // (파란색은 리스트 선택 하이라이트와 겹쳐서 teal 사용)
    var color: Color { .teal }
}

