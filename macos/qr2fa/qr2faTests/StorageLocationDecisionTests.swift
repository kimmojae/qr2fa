import XCTest
@testable import qr2fa

/// "어느 대상 상태에 어떤 전략을 쓰고, 언제 반드시 묻는가" — 이 앱에서 가장 파괴적인 분기다.
/// 회귀 방지의 핵심은 두 가지: **대상에 다른 계정이 있으면 반드시 확인을 거친다**,
/// 그리고 **내용이 같으면 묻지 않는다**.
final class StorageLocationDecisionTests: XCTestCase {

    private func makeTempDir() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.path
    }

    private func writeStorage(at path: String, issuer: String) throws {
        let account = Account(
            id: 1, name: "user@example.com", issuer: issuer,
            secret: "JBSWY3DPEHPK3PXP", tag: "",
            algorithm: "SHA1", digits: 6, period: 30, createdAt: Date()
        )
        let storage = AccountStorage(version: "1.0", nextId: 1, accounts: [account])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try encoder.encode(storage).write(to: URL(fileURLWithPath: path))
    }

    // MARK: - 순수 판단

    func test_decide_samePathIsNoChange() {
        XCTAssertEqual(
            StorageLocationDecision.decide(
                currentPath: "/a/accounts.json",
                targetPath: "/a/accounts.json",
                targetState: .accounts(count: 9),
                contentsIdentical: true
            ),
            .noChange
        )
    }

    /// 대상에 다른 계정 파일이 있으면 예외 없이 묻는다. 이게 무너지면 복구 불가능한
    /// 시크릿이 조용히 덮인다.
    func test_decide_targetHasAccounts_alwaysAsks() {
        XCTAssertEqual(
            StorageLocationDecision.decide(
                currentPath: "/a/accounts.json",
                targetPath: "/b/accounts.json",
                targetState: .accounts(count: 3),
                contentsIdentical: false
            ),
            .askWhichWins(targetCount: 3)
        )
    }

    /// 계정 0개짜리 파일이라도 파일은 파일이다 — 묻지 않고 덮으면 안 된다.
    func test_decide_targetHasEmptyAccountsFile_stillAsks() {
        XCTAssertEqual(
            StorageLocationDecision.decide(
                currentPath: "/a/accounts.json",
                targetPath: "/b/accounts.json",
                targetState: .accounts(count: 0),
                contentsIdentical: false
            ),
            .askWhichWins(targetCount: 0)
        )
    }

    /// 두 파일이 바이트 단위로 같으면 물어봐야 할 게 없다. "기본 폴더 ↔ iCloud" 왕복에서
    /// 매번 3버튼 경고가 뜨면, 진짜 파괴적인 순간의 경고까지 같이 클릭당한다.
    func test_decide_identicalContents_doesNotAsk() {
        XCTAssertEqual(
            StorageLocationDecision.decide(
                currentPath: "/a/accounts.json",
                targetPath: "/b/accounts.json",
                targetState: .accounts(count: 11),
                contentsIdentical: true
            ),
            .proceed(.adoptTarget)
        )
    }

    /// 내용이 같을 땐 백업도 복사도 없이 포인터만 옮긴다 — `.bak-*`가 iCloud로
    /// 동기화돼 전 Mac에 쌓이면 안 된다.
    func test_decide_identicalContents_adoptsInsteadOfCopying() {
        guard case .proceed(let strategy) = StorageLocationDecision.decide(
            currentPath: "/a/accounts.json",
            targetPath: "/b/accounts.json",
            targetState: .accounts(count: 11),
            contentsIdentical: true
        ) else { return XCTFail("proceed를 기대했다") }
        XCTAssertEqual(strategy, .adoptTarget)
    }

    func test_decide_targetAbsent_proceedsWithoutAsking() {
        XCTAssertEqual(
            StorageLocationDecision.decide(
                currentPath: "/a/accounts.json",
                targetPath: "/b/accounts.json",
                targetState: .absent,
                contentsIdentical: false
            ),
            .proceed(.copyCurrent)
        )
    }

    func test_decide_targetUnreadable_asks() {
        XCTAssertEqual(
            StorageLocationDecision.decide(
                currentPath: "/a/accounts.json",
                targetPath: "/b/accounts.json",
                targetState: .unreadable,
                contentsIdentical: false
            ),
            .askOverwriteUnreadable
        )
    }

    // MARK: - 실제 디스크 상태로 판단

    /// N3의 실제 시나리오 — 기본 폴더로 되돌렸다가 다시 iCloud를 고르는 왕복.
    func test_decide_onDisk_byteIdenticalRoundTripDoesNotAsk() throws {
        let current = "\(makeTempDir())/accounts.json"
        let target = "\(makeTempDir())/accounts.json"
        try writeStorage(at: current, issuer: "AWS")
        try FileManager.default.copyItem(atPath: current, toPath: target)

        XCTAssertEqual(
            StorageLocationDecision.decide(currentPath: current, targetPath: target),
            .proceed(.adoptTarget)
        )
    }

    /// 계정 집합이 같아도 바이트가 다르면 묻는다 — 바이트 비교에서 끊는 게 오탐 0이다.
    func test_decide_onDisk_differentContentsAsks() throws {
        let current = "\(makeTempDir())/accounts.json"
        let target = "\(makeTempDir())/accounts.json"
        try writeStorage(at: current, issuer: "AWS")
        try writeStorage(at: target, issuer: "GitHub")

        XCTAssertEqual(
            StorageLocationDecision.decide(currentPath: current, targetPath: target),
            .askWhichWins(targetCount: 1)
        )
    }

    /// 현재 파일이 없으면 contentsEqual이 false를 돌려주므로 "같다"로 오판하지 않는다.
    func test_decide_onDisk_missingCurrentFileIsNotIdentical() throws {
        let current = "\(makeTempDir())/accounts.json"   // 만들지 않는다
        let target = "\(makeTempDir())/accounts.json"
        try writeStorage(at: target, issuer: "AWS")

        XCTAssertEqual(
            StorageLocationDecision.decide(currentPath: current, targetPath: target),
            .askWhichWins(targetCount: 1)
        )
    }

    /// 양쪽 다 없으면 "둘 다 빈 파일"로 오판하면 안 된다 — 대상이 없으니 그냥 진행.
    func test_decide_onDisk_bothMissingProceeds() {
        XCTAssertEqual(
            StorageLocationDecision.decide(
                currentPath: "\(makeTempDir())/accounts.json",
                targetPath: "\(makeTempDir())/accounts.json"
            ),
            .proceed(.copyCurrent)
        )
    }
}
