import AppKit
import SwiftUI

/// 태그 색은 프리셋 없이 하나로 통일한다. 설정 창과 메뉴바가 같은 값을 쓰도록 여기서만 정의한다.
/// (파란색은 리스트 선택 하이라이트와 겹쳐서 teal 사용)
enum TagPalette {
    static let color = Color.teal
    static let nsColor = NSColor(color)
}

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

    var color: Color { TagPalette.color }
}

