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

    var color: Color {
        switch tag.lowercased() {
        case "prod":    return .orange
        case "dev":     return .blue
        case "staging": return .purple
        case "rnd":     return .green
        case "all":     return .purple
        default:        return .secondary
        }
    }
}

struct TagSelectorPopover: View {
    @Binding var tag: String
    @State private var customInput = ""
    let presets = ["prod", "dev", "staging", "rnd"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("태그 변경")
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(presets, id: \.self) { preset in
                    TagBadgeView(tag: preset)
                        .onTapGesture { tag = preset }
                        .opacity(tag == preset ? 1.0 : 0.5)
                        .scaleEffect(tag == preset ? 1.05 : 1.0)
                        .animation(.easeOut(duration: 0.1), value: tag)
                }
                TagBadgeView(tag: "")
                    .onTapGesture { tag = "" }
                    .opacity(tag.isEmpty ? 1.0 : 0.5)
            }

            HStack(spacing: 6) {
                TextField("직접 입력", text: $customInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit {
                        let trimmed = customInput.trimmingCharacters(in: .whitespaces).lowercased()
                        if !trimmed.isEmpty { tag = trimmed }
                        customInput = ""
                    }
                Button("적용") {
                    let trimmed = customInput.trimmingCharacters(in: .whitespaces).lowercased()
                    if !trimmed.isEmpty { tag = trimmed }
                    customInput = ""
                }
                .font(.system(size: 11))
                .disabled(customInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}

/// 가로 공간이 모자라면 다음 줄로 흐르게 배치하는 간단한 Layout.
/// 태그 프리셋처럼 개수·길이가 가변인 뱃지들을 한 줄에 욱여넣지 않고 자연스럽게 감싼다.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxRowWidth = max(maxRowWidth, x - spacing)
        }
        return CGSize(width: min(maxRowWidth, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
