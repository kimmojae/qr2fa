import XCTest
@testable import qr2fa

final class StorageServiceTests: XCTestCase {

    private var tempPath: String!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempPath = dir.appendingPathComponent("accounts.json").path
    }

    override func tearDown() {
        let dir = URL(fileURLWithPath: tempPath).deletingLastPathComponent().path
        try? FileManager.default.removeItem(atPath: dir)
        super.tearDown()
    }

    func test_loadEmptyWhenFileAbsent() throws {
        let service = StorageService(path: tempPath)
        try service.load()
        XCTAssertTrue(service.accounts.isEmpty)
    }

    func test_addAndPersist() throws {
        let service = StorageService(path: tempPath)
        try service.load()

        let account = Account(
            id: 0, name: "user", issuer: "GitHub",
            secret: "JBSWY3DPEHPK3PXP", tag: "dev",
            algorithm: "SHA1", digits: 6, period: 30,
            createdAt: Date()
        )
        try service.add(account)

        XCTAssertEqual(service.accounts.count, 1)
        XCTAssertEqual(service.accounts[0].id, 1)
        XCTAssertEqual(service.accounts[0].issuer, "GitHub")

        // Reload from disk — verify persistence
        let service2 = StorageService(path: tempPath)
        try service2.load()
        XCTAssertEqual(service2.accounts.count, 1)
        XCTAssertEqual(service2.accounts[0].issuer, "GitHub")
    }

    func test_update() throws {
        let service = StorageService(path: tempPath)
        try service.load()

        let account = Account(
            id: 0, name: "user", issuer: "GitHub",
            secret: "JBSWY3DPEHPK3PXP", tag: "dev",
            algorithm: "SHA1", digits: 6, period: 30,
            createdAt: Date()
        )
        try service.add(account)
        var saved = service.accounts[0]
        saved.tag = "prod"
        try service.update(saved)

        XCTAssertEqual(service.accounts[0].tag, "prod")
    }

    func test_delete() throws {
        let service = StorageService(path: tempPath)
        try service.load()

        let account = Account(
            id: 0, name: "user", issuer: "GitHub",
            secret: "JBSWY3DPEHPK3PXP", tag: "",
            algorithm: "SHA1", digits: 6, period: 30,
            createdAt: Date()
        )
        try service.add(account)
        let id = service.accounts[0].id
        try service.delete(id: id)

        XCTAssertTrue(service.accounts.isEmpty)
    }

    func test_readExistingCLIFile() throws {
        // Write a file in the same format the Go CLI produces
        let json = """
        {
          "version": "1.0",
          "nextId": 3,
          "accounts": [
            {
              "id": 1, "name": "alice", "issuer": "AWS",
              "secret": "JBSWY3DPEHPK3PXP", "tag": "prod",
              "algorithm": "SHA1", "digits": 6, "period": 30,
              "createdAt": "2025-01-01T00:00:00Z"
            }
          ]
        }
        """
        try json.write(toFile: tempPath, atomically: true, encoding: .utf8)

        let service = StorageService(path: tempPath)
        try service.load()

        XCTAssertEqual(service.accounts.count, 1)
        XCTAssertEqual(service.accounts[0].name, "alice")
        XCTAssertEqual(service.accounts[0].issuer, "AWS")
    }

    func test_updateNonexistent_throws() throws {
        let service = StorageService(path: tempPath)
        try service.load()

        let nonexistent = Account(
            id: 999, name: "ghost", issuer: "None",
            secret: "JBSWY3DPEHPK3PXP", tag: "",
            algorithm: "SHA1", digits: 6, period: 30,
            createdAt: Date()
        )
        XCTAssertThrowsError(try service.update(nonexistent))
    }

    // MARK: - Location resolution

    /// UserDefaults.standard를 오염시키지 않도록 테스트마다 별도 suite를 쓴다.
    private func makeDefaults() -> UserDefaults {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return defaults
    }

    func test_needsLocationChoice_trueWhenKeyAbsent() {
        let defaults = makeDefaults()
        let service = StorageService(path: tempPath, defaults: defaults)
        XCTAssertTrue(service.needsLocationChoice)
    }

    func test_needsLocationChoice_trueWhenKeyEmpty() {
        let defaults = makeDefaults()
        defaults.set("", forKey: StorageService.storageDirectoryKey)
        let service = StorageService(path: tempPath, defaults: defaults)
        XCTAssertTrue(service.needsLocationChoice)
    }

    func test_needsLocationChoice_falseWhenKeyPresent() {
        let defaults = makeDefaults()
        defaults.set("/tmp/whatever", forKey: StorageService.storageDirectoryKey)
        let service = StorageService(path: tempPath, defaults: defaults)
        XCTAssertFalse(service.needsLocationChoice)
    }

    func test_resolveDefaultPath_usesStoredDirectory() {
        let defaults = makeDefaults()
        defaults.set("/tmp/qr2fa-test", forKey: StorageService.storageDirectoryKey)
        XCTAssertEqual(
            StorageService.resolveDefaultPath(defaults: defaults),
            "/tmp/qr2fa-test/accounts.json"
        )
    }

    /// 이번 변경의 핵심 회귀 방지 — iCloud Drive 폴더가 실제로 존재하는 Mac에서도
    /// 저장된 선택이 없으면 iCloud를 고르지 않고 로컬 기본값으로 떨어져야 한다.
    func test_resolveDefaultPath_neverInfersICloud() {
        let defaults = makeDefaults()
        XCTAssertEqual(
            StorageService.resolveDefaultPath(defaults: defaults),
            "\(StorageService.localDefaultDirectory())/accounts.json"
        )
    }

    func test_localDefaultDirectory_isConfigQr2fa() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(StorageService.localDefaultDirectory(), "\(home)/.config/qr2fa")
    }

    // MARK: - commitInitialLocation

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

    /// 새 Mac에서 iCloud를 고르는 정상 경로 — 대상에 이미 있는 계정을 그대로 읽어야 한다.
    func test_commitInitialLocation_keepsExistingTargetFile() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try writeStorage(at: "\(targetDir)/accounts.json", issuer: "TargetService")

        // 임시 경로에도 다른 파일이 있는 상태(온보딩을 닫고 계정을 추가한 경우)
        try writeStorage(at: tempPath, issuer: "ProvisionalService")

        let service = StorageService(path: tempPath, defaults: defaults)
        try service.commitInitialLocation(directory: targetDir)

        XCTAssertEqual(service.storagePath, "\(targetDir)/accounts.json")
        XCTAssertEqual(service.accounts.first?.issuer, "TargetService")
        // 임시 파일은 그대로 남아 있어야 한다 (지우지 않음)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))
    }

    /// 대상이 비어 있으면 온보딩 중 임시로 쌓인 계정을 옮겨 간다.
    func test_commitInitialLocation_movesProvisionalFile() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try writeStorage(at: tempPath, issuer: "ProvisionalService")

        let service = StorageService(path: tempPath, defaults: defaults)
        try service.commitInitialLocation(directory: targetDir)

        XCTAssertEqual(service.accounts.first?.issuer, "ProvisionalService")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath))
    }

    func test_commitInitialLocation_emptyStart() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()

        let service = StorageService(path: tempPath, defaults: defaults)
        try service.commitInitialLocation(directory: targetDir)

        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertEqual(service.storagePath, "\(targetDir)/accounts.json")
    }

    func test_commitInitialLocation_persistsChoice() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()

        let service = StorageService(path: tempPath, defaults: defaults)
        try service.commitInitialLocation(directory: targetDir)

        XCTAssertEqual(defaults.string(forKey: StorageService.storageDirectoryKey), targetDir)
        XCTAssertFalse(service.needsLocationChoice)
    }

    /// 온보딩 창을 닫고 계정을 추가한 뒤, 이미 파일이 있는 폴더를 고른 경우 —
    /// 임시 파일이 남는다는 사실을 결과로 알려야 한다(조용히 고아가 되면 안 된다).
    func test_commitInitialLocation_reportsLeftBehindAccounts() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try writeStorage(at: "\(targetDir)/accounts.json", issuer: "TargetService")
        try writeStorage(at: tempPath, issuer: "ProvisionalService")

        let service = StorageService(path: tempPath, defaults: defaults)
        let outcome = try service.commitInitialLocation(directory: targetDir)

        XCTAssertTrue(outcome.hasNotice)
        XCTAssertEqual(outcome.leftBehindPath, tempPath)
        XCTAssertEqual(outcome.leftBehindCount, 1)
        XCTAssertNil(outcome.loadError)
    }

    /// 정상 경로에서는 알릴 게 없어야 한다 — 매번 경고창이 뜨면 안 된다.
    func test_commitInitialLocation_noNoticeOnCleanCommit() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try writeStorage(at: tempPath, issuer: "ProvisionalService")

        let service = StorageService(path: tempPath, defaults: defaults)
        let outcome = try service.commitInitialLocation(directory: targetDir)

        XCTAssertFalse(outcome.hasNotice)
        XCTAssertNil(outcome.leftBehindPath)
    }

    /// 대상 파일이 손상돼 로드가 실패해도 위치 확정은 성공으로 끝나야 한다.
    /// 던져버리면 온보딩에서 같은 예외가 무한 반복되며 빠져나갈 수 없다.
    func test_commitInitialLocation_commitsEvenWhenTargetUnreadable() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try "{ not json".write(
            toFile: "\(targetDir)/accounts.json", atomically: true, encoding: .utf8
        )

        let service = StorageService(path: tempPath, defaults: defaults)
        let outcome = try service.commitInitialLocation(directory: targetDir)

        XCTAssertNotNil(outcome.loadError)
        XCTAssertTrue(outcome.hasNotice)
        // 선택은 영속화됐고 경로도 옮겨갔다 — 다시 시도할 게 아니라 창을 닫아야 하는 상태.
        XCTAssertEqual(service.storagePath, "\(targetDir)/accounts.json")
        XCTAssertFalse(service.needsLocationChoice)
    }

    // MARK: - changePath

    /// 핵심 안전장치 — 대상 파일을 unlink하지 않는다. 이 앱의 데이터는 복구 불가능한 시크릿이다.
    func test_changePath_copyCurrent_backsUpTargetInsteadOfDeleting() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        let target = "\(targetDir)/accounts.json"
        try writeStorage(at: target, issuer: "TargetService")
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let service = StorageService(path: tempPath, defaults: defaults)
        try service.load()
        let backup = try service.changePath(to: target, strategy: .copyCurrent)

        XCTAssertEqual(service.accounts.first?.issuer, "CurrentService")

        // 덮인 파일은 사라지지 않고 백업으로 남아 있어야 한다.
        let backupPath = try XCTUnwrap(backup)
        XCTAssertTrue(backupPath.hasPrefix("\(target).bak-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath))
        XCTAssertEqual(
            StorageService.inspectFile(at: backupPath), .accounts(count: 1)
        )
        let restored = StorageService(path: backupPath, defaults: makeDefaults())
        try restored.load()
        XCTAssertEqual(restored.accounts.first?.issuer, "TargetService")
    }

    /// 여러 Mac을 iCloud로 합칠 때의 정상 경로 — 대상 파일을 정본으로 삼고 아무것도 덮지 않는다.
    func test_changePath_adoptTarget_leavesBothFilesIntact() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        let target = "\(targetDir)/accounts.json"
        try writeStorage(at: target, issuer: "TargetService")
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let service = StorageService(path: tempPath, defaults: defaults)
        try service.load()
        let backup = try service.changePath(to: target, strategy: .adoptTarget)

        XCTAssertNil(backup)
        XCTAssertEqual(service.accounts.first?.issuer, "TargetService")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: targetDir), ["accounts.json"]
        )
    }

    func test_changePath_targetAbsent_carriesAccountsOver() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let service = StorageService(path: tempPath, defaults: defaults)
        try service.load()
        try service.changePath(to: "\(targetDir)/accounts.json", strategy: .copyCurrent)

        XCTAssertEqual(service.accounts.first?.issuer, "CurrentService")
        XCTAssertEqual(defaults.string(forKey: StorageService.storageDirectoryKey), targetDir)
    }

    /// 같은 경로를 다시 고르면 아무 일도 없어야 한다 — 백업으로 원본을 치워버리면
    /// 이어지는 복사의 원본이 사라진다.
    func test_changePath_sameFileIsNoOp() throws {
        let defaults = makeDefaults()
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let service = StorageService(path: tempPath, defaults: defaults)
        let backup = try service.changePath(to: tempPath, strategy: .copyCurrent)

        XCTAssertNil(backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))
        XCTAssertEqual(service.accounts.first?.issuer, "CurrentService")
    }

    func test_backupIfPresent_doesNotCollideWithinSameSecond() throws {
        let dir = makeTempDir()
        let path = "\(dir)/accounts.json"
        try writeStorage(at: path, issuer: "First")
        let first = try XCTUnwrap(StorageService.backupIfPresent(path))
        try writeStorage(at: path, issuer: "Second")
        let second = try XCTUnwrap(StorageService.backupIfPresent(path))

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second))
    }

    func test_backupIfPresent_returnsNilWhenAbsent() throws {
        XCTAssertNil(try StorageService.backupIfPresent("\(makeTempDir())/nope.json"))
    }

    // MARK: - resetToDefaultPath

    /// 복원 후에도 온보딩이 다시 뜨면 안 된다.
    func test_resetToDefaultPath_keepsStoredChoice() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        let defaultDir = makeTempDir()

        let service = StorageService(
            path: tempPath, defaults: defaults, defaultDirectory: defaultDir
        )
        try service.commitInitialLocation(directory: targetDir)
        try service.resetToDefaultPath(strategy: .copyCurrent)

        XCTAssertFalse(service.needsLocationChoice)
        XCTAssertTrue(service.isDefaultPath)
    }

    /// 이 브랜치의 존재 이유에 대한 회귀 방지 — 되돌리기가 포인터만 옮기고 계정을
    /// 두고 오면, 사용자에게는 계정이 전부 사라진 것으로 보인다.
    func test_resetToDefaultPath_carriesAccountsToEmptyDefaultFolder() throws {
        let defaults = makeDefaults()
        let iCloudDir = makeTempDir()
        let defaultDir = makeTempDir()   // 비어 있는 기본 폴더
        try writeStorage(at: "\(iCloudDir)/accounts.json", issuer: "ICloudService")

        let service = StorageService(
            path: "\(iCloudDir)/accounts.json", defaults: defaults, defaultDirectory: defaultDir
        )
        try service.load()
        try service.resetToDefaultPath(strategy: .copyCurrent)

        XCTAssertEqual(service.storagePath, "\(defaultDir)/accounts.json")
        XCTAssertEqual(service.accounts.first?.issuer, "ICloudService")
        // 원본도 그대로 남는다 — 되돌리기는 복사지 이사가 아니다.
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(iCloudDir)/accounts.json"))
    }

    /// 기본 폴더에 이미 파일이 있으면(당황해서 계정을 다시 등록한 경우) 그것도 백업된다.
    func test_resetToDefaultPath_backsUpExistingDefaultFile() throws {
        let defaults = makeDefaults()
        let iCloudDir = makeTempDir()
        let defaultDir = makeTempDir()
        try writeStorage(at: "\(iCloudDir)/accounts.json", issuer: "ICloudService")
        try writeStorage(at: "\(defaultDir)/accounts.json", issuer: "ReRegistered")

        let service = StorageService(
            path: "\(iCloudDir)/accounts.json", defaults: defaults, defaultDirectory: defaultDir
        )
        try service.load()
        let backup = try XCTUnwrap(service.resetToDefaultPath(strategy: .copyCurrent))

        XCTAssertEqual(service.accounts.first?.issuer, "ICloudService")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup))
    }

    // MARK: - inspectTarget

    func test_inspectTarget_absent() {
        XCTAssertEqual(StorageService.inspectTarget(directory: makeTempDir()), .absent)
    }

    func test_inspectTarget_countsAccounts() throws {
        let dir = makeTempDir()
        try writeStorage(at: "\(dir)/accounts.json", issuer: "AWS")
        XCTAssertEqual(StorageService.inspectTarget(directory: dir), .accounts(count: 1))
    }

    func test_inspectTarget_unreadable() throws {
        let dir = makeTempDir()
        try "not json".write(toFile: "\(dir)/accounts.json", atomically: true, encoding: .utf8)
        XCTAssertEqual(StorageService.inspectTarget(directory: dir), .unreadable)
    }
}
