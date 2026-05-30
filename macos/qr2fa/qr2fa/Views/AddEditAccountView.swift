import SwiftUI

struct AddEditAccountView: View {
    enum Mode {
        case add
        case edit(Account)
    }

    let mode: Mode
    @Environment(StorageService.self) private var storageService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text(isEditing ? "계정 편집" : "계정 추가")
                .font(.headline)
            Text("(Task 10에서 구현)")
                .foregroundStyle(.secondary)
            Button("닫기") { dismiss() }
        }
        .frame(width: 380, height: 200)
        .padding()
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }
}
