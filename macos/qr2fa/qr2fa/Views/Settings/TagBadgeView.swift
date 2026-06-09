import SwiftUI

struct TagBadgeView: View {
    let tag: String
    var showEditHint: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Text(tag.isEmpty ? "태그 추가" : tag)
                .font(.system(size: 9, weight: .medium))
            if showEditHint {
                Image(systemName: "pencil")
                    .font(.system(size: 7))
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(tag.isEmpty ? color.opacity(0.4) : .clear, style: StrokeStyle(lineWidth: 1, dash: [3]))
        )
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

            HStack(spacing: 6) {
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
