import Foundation

/// 저장 위치 변경 요청에 대해 무엇을 할지 — 그리고 **언제 반드시 물어야 하는지** — 정한다.
///
/// 이 앱에서 가장 파괴적인 분기라 뷰에 두면 안 됐다. `NSAlert`와 얽혀 있으면 테스트가 모달에서
/// 멈추기 때문에 판단만 순수 함수로 떼어냈다. 뷰는 결과대로 묻고 움직이기만 한다.
enum StorageLocationDecision: Equatable {
    /// 이미 그 위치다. 아무것도 하지 않는다.
    case noChange
    /// 물어볼 것 없이 바로 진행한다.
    case proceed(StorageService.PathChangeStrategy)
    /// 대상에 다른 계정 파일이 있다 — 어느 쪽을 정본으로 삼을지 반드시 묻는다.
    case askWhichWins(targetCount: Int)
    /// 대상 파일을 읽을 수 없다 — 백업하고 덮어쓸지 묻는다.
    case askOverwriteUnreadable

    /// - Parameters:
    ///   - contentsIdentical: 두 파일이 바이트 단위로 같은가.
    static func decide(
        currentPath: String,
        targetPath: String,
        targetState: StorageService.TargetState,
        contentsIdentical: Bool
    ) -> StorageLocationDecision {
        guard currentPath != targetPath else { return .noChange }

        // 내용이 같으면 고를 게 없다. "기본 폴더 → iCloud → 다시 기본 폴더" 같은 왕복은
        // 가장 흔한 경로인데, 계정 개수만 보고 물으면 여기서도 3버튼 경고가 뜬다. 의미 없는
        // 경고가 기본이 되면 진짜 파괴적인 순간의 경고도 같이 클릭당한다.
        //
        // 계정 집합은 같은데 바이트가 다른 경우(포맷 차이)까지 묶지 않는다 —
        // 바이트 비교는 오탐이 0이라 여기서 끊는 게 맞다.
        if contentsIdentical { return .proceed(.adoptTarget) }

        switch targetState {
        case .absent:
            // 대상이 비어 있으면 지금 계정을 그대로 데려간다. 잃을 게 없으니 묻지 않는다.
            return .proceed(.copyCurrent)
        case .accounts(let count):
            return .askWhichWins(targetCount: count)
        case .unreadable:
            return .askOverwriteUnreadable
        }
    }

    /// 실제 디스크 상태를 읽어 판단한다.
    ///
    /// `FileManager.contentsEqual`은 어느 쪽이든 파일이 없으면 `false`를 돌려주므로
    /// 존재 여부를 따로 가드할 필요가 없다.
    static func decide(currentPath: String, targetPath: String) -> StorageLocationDecision {
        decide(
            currentPath: currentPath,
            targetPath: targetPath,
            targetState: StorageService.inspectFile(at: targetPath),
            contentsIdentical: FileManager.default.contentsEqual(
                atPath: currentPath, andPath: targetPath
            )
        )
    }
}
