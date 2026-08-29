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

    /// 테스트용 서비스. 실제 Keychain을 절대 건드리지 않는다.
    private func makeService(
        path: String? = nil,
        defaults: UserDefaults? = nil,
        defaultDirectory: String? = nil,
        keyStore: KeyStore = InMemoryKeyStore()
    ) -> StorageService {
        StorageService(
            path: path ?? tempPath,
            defaults: defaults ?? UserDefaults(suiteName: UUID().uuidString)!,
            defaultDirectory: defaultDirectory ?? URL(fileURLWithPath: tempPath)
                .deletingLastPathComponent().path,
            keyStore: keyStore
        )
    }

    func test_defaultStateIsUnlocked() throws {
        let service = makeService()
        try service.load()
        XCTAssertEqual(service.state, .unlocked)
    }

    func test_loadEmptyWhenFileAbsent() throws {
        let service = makeService(path: tempPath)
        try service.load()
        XCTAssertTrue(service.accounts.isEmpty)
    }

    func test_addAndPersist() throws {
        // 재오픈 서비스가 같은 키를 봐야 하므로 keyStore를 공유한다 — 실제로는
        // KeychainKeyStore가 이 역할을 한다.
        let keyStore = InMemoryKeyStore()
        let service = makeService(path: tempPath, keyStore: keyStore)
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
        let service2 = makeService(path: tempPath, keyStore: keyStore)
        try service2.load()
        XCTAssertEqual(service2.accounts.count, 1)
        XCTAssertEqual(service2.accounts[0].issuer, "GitHub")
    }

    func test_update() throws {
        let service = makeService(path: tempPath)
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
        let service = makeService(path: tempPath)
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

    // MARK: - Write guards

    func test_addRefusedWhenLocked() throws {
        let seeded = makeService(keyStore: InMemoryKeyStore())
        try seeded.load()
        try seeded.add(sampleAccount())
        let before = try Data(contentsOf: URL(fileURLWithPath: tempPath))

        let locked = makeService(keyStore: InMemoryKeyStore())
        try locked.load()
        XCTAssertEqual(locked.state, .locked)

        XCTAssertThrowsError(try locked.add(sampleAccount()))
        XCTAssertTrue(locked.accounts.isEmpty,
                      "save()가 던지기 전에 이미 메모리의 accounts를 바꿔놓았다")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: tempPath)), before,
                       "잠긴 상태에서 파일을 건드리면 계정이 사라진다")
    }

    func test_deleteRefusedWhenNeedsMigration() throws {
        try writeLegacyFile(accountCount: 1)
        let before = try Data(contentsOf: URL(fileURLWithPath: tempPath))

        let service = makeService()
        try service.load()
        XCTAssertEqual(service.state, .needsMigration)

        XCTAssertThrowsError(try service.delete(id: 1))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: tempPath)), before)
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

        let service = makeService(path: tempPath)
        try service.load()
        // v1 평문 파일은 이제 즉시 싣지 않고 마이그레이션을 기다린다.
        try service.migrateToEncrypted()

        XCTAssertEqual(service.accounts.count, 1)
        XCTAssertEqual(service.accounts[0].name, "alice")
        XCTAssertEqual(service.accounts[0].issuer, "AWS")
    }

    func test_updateNonexistent_throws() throws {
        let service = makeService(path: tempPath)
        try service.load()

        let nonexistent = Account(
            id: 999, name: "ghost", issuer: "None",
            secret: "JBSWY3DPEHPK3PXP", tag: "",
            algorithm: "SHA1", digits: 6, period: 30,
            createdAt: Date()
        )
        XCTAssertThrowsError(try service.update(nonexistent))
    }

    // MARK: - v2 encryption / migration

    func test_savesAsEncryptedV2() throws {
        let service = makeService()
        try service.load()
        try service.add(sampleAccount())

        let raw = try Data(contentsOf: URL(fileURLWithPath: tempPath))
        guard case .v2 = try VaultCrypto.detect(raw) else {
            return XCTFail("저장 파일이 v2 봉투여야 한다")
        }
        XCTAssertFalse(String(data: raw, encoding: .utf8)!.contains("JBSWY3DPEHPK3PXP"),
                       "시크릿이 평문으로 남아 있으면 안 된다")
    }

    func test_reloadsWithSameKey() throws {
        let keyStore = InMemoryKeyStore()
        let service = makeService(keyStore: keyStore)
        try service.load()
        try service.add(sampleAccount())

        let reopened = makeService(keyStore: keyStore)
        try reopened.load()
        XCTAssertEqual(reopened.state, .unlocked)
        XCTAssertEqual(reopened.accounts.count, 1)
        XCTAssertEqual(reopened.accounts[0].secret, "JBSWY3DPEHPK3PXP")
    }

    func test_lockedWhenKeyMissing() throws {
        let service = makeService(keyStore: InMemoryKeyStore())
        try service.load()
        try service.add(sampleAccount())

        let noKey = makeService(keyStore: InMemoryKeyStore())   // 키 없는 새 저장소
        try noKey.load()
        XCTAssertEqual(noKey.state, .locked)
        XCTAssertTrue(noKey.accounts.isEmpty, "잠긴 상태에서 계정을 노출하면 안 된다")
    }

    func test_v1FileNeedsMigration() throws {
        try writeLegacyFile(accountCount: 1)
        let service = makeService()
        try service.load()

        XCTAssertEqual(service.state, .needsMigration)
        XCTAssertTrue(service.accounts.isEmpty, "마이그레이션 전에는 계정을 싣지 않는다")
    }

    func test_migrationEncryptsAndKeepsOriginal() throws {
        try writeLegacyFile(accountCount: 1)
        let service = makeService()
        try service.load()
        try service.migrateToEncrypted()

        XCTAssertEqual(service.state, .unlocked)
        XCTAssertEqual(service.accounts.count, 1)

        let raw = try Data(contentsOf: URL(fileURLWithPath: tempPath))
        guard case .v2 = try VaultCrypto.detect(raw) else { return XCTFail("v2여야 한다") }

        let backup = try XCTUnwrap(service.lastMigrationBackupPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup),
                      "평문 원본은 삭제하지 않고 .old- 로 남긴다")
        XCTAssertEqual(StorageService.inspectFile(at: backup), .accounts(count: 1))
    }

    func test_unknownVersionIsUnreadableAndNotOverwritten() throws {
        let future = Data(#"{"version":"9","accountCount":0,"sealed":"AAAA"}"#.utf8)
        try future.write(to: URL(fileURLWithPath: tempPath))

        let service = makeService()
        try service.load()

        // 메시지 문구가 아니라 케이스만 본다 — 문구는 바뀔 수 있다
        guard case .unreadable = service.state else {
            return XCTFail("모르는 version은 .unreadable 이어야 한다: \(service.state)")
        }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: tempPath)), future,
                       "읽지 못한 파일을 건드리면 안 된다")
    }

    func test_changePathKeepsAccountsDecryptable() throws {
        let keyStore = InMemoryKeyStore()
        let service = makeService(keyStore: keyStore)
        try service.load()
        try service.add(sampleAccount())

        let otherDir = URL(fileURLWithPath: tempPath)
            .deletingLastPathComponent()
            .appendingPathComponent("moved").path
        try StorageService.createDirectory(otherDir)
        let moved = "\(otherDir)/accounts.json"

        try service.changePath(to: moved, strategy: .copyCurrent)

        XCTAssertEqual(service.state, .unlocked)
        XCTAssertEqual(service.accounts.count, 1)
        XCTAssertEqual(service.accounts[0].secret, "JBSWY3DPEHPK3PXP")
    }

    func test_filePermissionsStay0600AfterEncryptedSave() throws {
        let service = makeService()
        try service.load()
        try service.add(sampleAccount())

        let attrs = try FileManager.default.attributesOfItem(atPath: tempPath)
        XCTAssertEqual(attrs[.posixPermissions] as? Int, 0o600)
    }

    // MARK: - 헬퍼

    private func sampleAccount() -> Account {
        Account(id: 0, name: "user", issuer: "GitHub",
                secret: "JBSWY3DPEHPK3PXP", tag: "dev",
                algorithm: "SHA1", digits: 6, period: 30, createdAt: Date())
    }

    private func writeLegacyFile(accountCount: Int) throws {
        let accounts = (1...max(accountCount, 1)).prefix(accountCount).map { i in
            Account(id: i, name: "user\(i)", issuer: "GitHub",
                    secret: "JBSWY3DPEHPK3PXP", tag: "", algorithm: "SHA1",
                    digits: 6, period: 30, createdAt: Date())
        }
        let storage = AccountStorage(version: "1.0", nextId: accountCount, accounts: Array(accounts))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(storage).write(to: URL(fileURLWithPath: tempPath))
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
        let service = makeService(path: tempPath, defaults: defaults)
        XCTAssertTrue(service.needsLocationChoice)
    }

    func test_needsLocationChoice_trueWhenKeyEmpty() {
        let defaults = makeDefaults()
        defaults.set("", forKey: StorageService.storageDirectoryKey)
        let service = makeService(path: tempPath, defaults: defaults)
        XCTAssertTrue(service.needsLocationChoice)
    }

    func test_needsLocationChoice_falseWhenKeyPresent() {
        let defaults = makeDefaults()
        defaults.set("/tmp/whatever", forKey: StorageService.storageDirectoryKey)
        let service = makeService(path: tempPath, defaults: defaults)
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

        let service = makeService(path: tempPath, defaults: defaults)
        try service.commitInitialLocation(directory: targetDir)
        // 대상 파일은 v1 평문이라 즉시 싣지 않고 마이그레이션을 기다린다.
        try service.migrateToEncrypted()

        XCTAssertEqual(service.storagePath, "\(targetDir)/accounts.json")
        XCTAssertEqual(service.accounts.first?.issuer, "TargetService")
        // 임시 파일의 내용은 지우지 않는다 — 이름만 예전 버전으로 바꿔 둔다.
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath))
        XCTAssertEqual(try oldCopies(of: tempPath).count, 1)
    }

    /// 대상이 비어 있으면 온보딩 중 임시로 쌓인 계정을 옮겨 간다.
    func test_commitInitialLocation_movesProvisionalFile() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try writeStorage(at: tempPath, issuer: "ProvisionalService")

        let service = makeService(path: tempPath, defaults: defaults)
        try service.commitInitialLocation(directory: targetDir)
        // 옮겨온 파일도 v1 평문이라 마이그레이션을 기다린다.
        try service.migrateToEncrypted()

        XCTAssertEqual(service.accounts.first?.issuer, "ProvisionalService")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath))
    }

    func test_commitInitialLocation_emptyStart() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()

        let service = makeService(path: tempPath, defaults: defaults)
        try service.commitInitialLocation(directory: targetDir)

        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertEqual(service.storagePath, "\(targetDir)/accounts.json")
    }

    func test_commitInitialLocation_persistsChoice() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()

        let service = makeService(path: tempPath, defaults: defaults)
        try service.commitInitialLocation(directory: targetDir)

        XCTAssertEqual(defaults.string(forKey: StorageService.storageDirectoryKey), targetDir)
        XCTAssertFalse(service.needsLocationChoice)
    }

    /// 온보딩 창을 닫고 계정을 추가한 뒤, 이미 파일이 있는 폴더를 고른 경우 —
    /// 임시 파일이 남는다는 사실을 결과로 알려야 한다(조용히 고아가 되면 안 된다).
    /// 대상에 이미 파일이 있어 임시 파일이 남는 경우, 그 파일은 예전 버전임이 이름에서
    /// 드러나야 한다 — 같은 이름으로 남아 있으면 어느 쪽이 정본인지 파일만 봐선 모른다.
    func test_commitInitialLocation_marksProvisionalFileAsOld() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try writeStorage(at: "\(targetDir)/accounts.json", issuer: "TargetService")
        try writeStorage(at: tempPath, issuer: "ProvisionalService")

        let service = makeService(path: tempPath, defaults: defaults)
        let outcome = try service.commitInitialLocation(directory: targetDir)

        // 예정대로 된 일은 알리지 않는다.
        XCTAssertFalse(outcome.hasNotice)
        XCTAssertNil(outcome.leftBehindPath, "이름을 바꿨으면 '그대로 남아 있다'가 아니다")
        let marked = try XCTUnwrap(outcome.markedOldPath)
        XCTAssertEqual(try oldCopies(of: tempPath), [marked])
        XCTAssertEqual(outcome.leftBehindCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath))
        // 내용은 그대로 살아 있어야 한다 — 복구 불가능한 시크릿이라 지우지 않는다.
        XCTAssertTrue(try storedIssuers(at: marked).contains("ProvisionalService"))
        XCTAssertNil(outcome.loadError)
    }

    /// 정상 경로에서는 알릴 게 없어야 한다 — 매번 경고창이 뜨면 안 된다.
    func test_commitInitialLocation_noNoticeOnCleanCommit() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try writeStorage(at: tempPath, issuer: "ProvisionalService")

        let service = makeService(path: tempPath, defaults: defaults)
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

        let service = makeService(path: tempPath, defaults: defaults)
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

        let service = makeService(path: tempPath, defaults: defaults)
        try service.load()
        let outcome = try service.changePath(to: target, strategy: .copyCurrent)
        // 옮겨간 파일도 v1 평문이라 마이그레이션을 기다린다.
        try service.migrateToEncrypted()

        XCTAssertEqual(service.accounts.first?.issuer, "CurrentService")

        // 덮인 파일은 사라지지 않고 백업으로 남아 있어야 한다.
        let backupPath = try XCTUnwrap(outcome.backupPath)
        XCTAssertTrue(backupPath.hasPrefix("\(target).bak-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath))
        XCTAssertEqual(
            StorageService.inspectFile(at: backupPath), .accounts(count: 1)
        )
        let restored = makeService(path: backupPath, defaults: makeDefaults())
        try restored.load()
        try restored.migrateToEncrypted()
        XCTAssertEqual(restored.accounts.first?.issuer, "TargetService")
    }

    /// 여러 Mac을 iCloud로 합칠 때의 정상 경로 — 대상 파일을 정본으로 삼고 아무것도 덮지 않는다.
    /// 이전 위치의 파일도 지우지 않는다(이름만 예전 버전으로 바뀐다).
    func test_changePath_adoptTarget_keepsBothFilesContents() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        let target = "\(targetDir)/accounts.json"
        try writeStorage(at: target, issuer: "TargetService")
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let service = makeService(path: tempPath, defaults: defaults)
        try service.load()
        let outcome = try service.changePath(to: target, strategy: .adoptTarget)
        // 대상 파일도 v1 평문이라 마이그레이션을 기다린다.
        try service.migrateToEncrypted()

        XCTAssertNil(outcome.backupPath)
        XCTAssertEqual(service.accounts.first?.issuer, "TargetService")
        XCTAssertEqual(try oldCopies(of: tempPath).count, 1)
        // 대상 폴더에 accounts.json만 남는다는 옛 단언은 더 이상 성립하지 않는다 — "원본은
        // 절대 삭제하지 않는다"는 불변식 때문에 adoptTarget으로 넘어온 v1 원본도
        // migrateToEncrypted가 .qr2fa 하위폴더에 .old-로 보존한다.
        XCTAssertEqual(try oldCopies(of: target).count, 1)
    }

    func test_changePath_targetAbsent_carriesAccountsOver() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let service = makeService(path: tempPath, defaults: defaults)
        try service.load()
        try service.changePath(to: "\(targetDir)/accounts.json", strategy: .copyCurrent)
        try service.migrateToEncrypted()

        XCTAssertEqual(service.accounts.first?.issuer, "CurrentService")
        XCTAssertEqual(defaults.string(forKey: StorageService.storageDirectoryKey), targetDir)
    }

    /// 같은 경로를 다시 고르면 아무 일도 없어야 한다 — 백업으로 원본을 치워버리면
    /// 이어지는 복사의 원본이 사라진다.
    func test_changePath_sameFileIsNoOp() throws {
        let defaults = makeDefaults()
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let service = makeService(path: tempPath, defaults: defaults)
        let outcome = try service.changePath(to: tempPath, strategy: .copyCurrent)
        try service.migrateToEncrypted()

        XCTAssertFalse(outcome.hasNotice)
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

    // MARK: - 기본 폴더로 되돌리기

    /// 되돌린 뒤에도 온보딩이 다시 뜨면 안 된다.
    func test_changePath_toDefaultDirectory_keepsStoredChoice() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        let defaultDir = makeTempDir()

        let service = makeService(
            path: tempPath, defaults: defaults, defaultDirectory: defaultDir
        )
        try service.commitInitialLocation(directory: targetDir)
        try service.changePath(to: "\(defaultDir)/accounts.json", strategy: .copyCurrent)

        XCTAssertFalse(service.needsLocationChoice)
        XCTAssertEqual(service.storagePath, "\(defaultDir)/accounts.json")
    }

    /// 이 브랜치의 존재 이유에 대한 회귀 방지 — 되돌리기가 포인터만 옮기고 계정을
    /// 두고 오면, 사용자에게는 계정이 전부 사라진 것으로 보인다.
    func test_changePath_toEmptyDefaultFolder_carriesAccountsOver() throws {
        let defaults = makeDefaults()
        let iCloudDir = makeTempDir()
        let defaultDir = makeTempDir()   // 비어 있는 기본 폴더
        try writeStorage(at: "\(iCloudDir)/accounts.json", issuer: "ICloudService")

        let service = makeService(
            path: "\(iCloudDir)/accounts.json", defaults: defaults, defaultDirectory: defaultDir
        )
        try service.load()
        try service.changePath(to: "\(defaultDir)/accounts.json", strategy: .copyCurrent)
        try service.migrateToEncrypted()

        XCTAssertEqual(service.storagePath, "\(defaultDir)/accounts.json")
        XCTAssertEqual(service.accounts.first?.issuer, "ICloudService")
        // 원본 내용도 남는다 — 되돌리기는 복사지 이사가 아니다. 다만 이름은 예전 버전으로 바뀐다.
        XCTAssertEqual(try oldCopies(of: "\(iCloudDir)/accounts.json").count, 1)
    }

    /// 기본 폴더에 이미 파일이 있으면(당황해서 계정을 다시 등록한 경우) 그것도 백업된다.
    func test_changePath_toDefaultFolderWithFile_backsItUp() throws {
        let defaults = makeDefaults()
        let iCloudDir = makeTempDir()
        let defaultDir = makeTempDir()
        try writeStorage(at: "\(iCloudDir)/accounts.json", issuer: "ICloudService")
        try writeStorage(at: "\(defaultDir)/accounts.json", issuer: "ReRegistered")

        let service = makeService(
            path: "\(iCloudDir)/accounts.json", defaults: defaults, defaultDirectory: defaultDir
        )
        try service.load()
        let outcome = try service.changePath(
            to: "\(defaultDir)/accounts.json", strategy: .copyCurrent
        )
        try service.migrateToEncrypted()

        XCTAssertEqual(service.accounts.first?.issuer, "ICloudService")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(outcome.backupPath)))
    }

    // MARK: - changePath: 실패·부분성공 경로

    /// 포인터를 확정한 뒤 로드가 실패해도 던지면 안 된다 — 던지면 변경은 이미 영속화됐는데
    /// 뷰는 "바꿀 수 없습니다"를 띄우고, 사용자는 어긋난 모델 위에서 계속 쓰게 된다.
    func test_changePath_loadFailureIsReportedNotThrown() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        let target = "\(targetDir)/accounts.json"
        try "{ not json".write(toFile: target, atomically: true, encoding: .utf8)
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let service = makeService(path: tempPath, defaults: defaults)
        try service.load()
        let outcome = try service.changePath(to: target, strategy: .adoptTarget)

        XCTAssertNotNil(outcome.loadError)
        XCTAssertTrue(outcome.hasNotice)
        // 위치 변경 자체는 성공했다 — 재시도가 아니라 고지가 필요한 상태.
        XCTAssertEqual(service.storagePath, target)
        XCTAssertEqual(defaults.string(forKey: StorageService.storageDirectoryKey), targetDir)
    }

    /// 알럿이 백업을 약속했으면 반드시 만들어야 한다. 현재 파일이 외부에서 사라졌다는 이유로
    /// 백업도 복사도 건너뛰면, 손상 파일 위에 포인터만 얹힌 뒤 다음 저장에서 그게 사라진다.
    func test_changePath_backsUpTargetEvenWhenCurrentFileIsGone() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        let target = "\(targetDir)/accounts.json"
        try "{ not json".write(toFile: target, atomically: true, encoding: .utf8)
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let service = makeService(path: tempPath, defaults: defaults)
        try service.load()
        // v1 평문 파일이라 이 시점엔 아직 계정이 실려 있지 않다 — 마이그레이션까지 마쳐야
        // "메모리의 계정은 살아 있다"는 이 테스트의 전제가 성립한다.
        try service.migrateToEncrypted()
        // 외부에서 현재 파일이 사라진 상황 (메모리의 계정은 살아 있다)
        try FileManager.default.removeItem(atPath: tempPath)

        let outcome = try service.changePath(to: target, strategy: .copyCurrent)

        let backupPath = try XCTUnwrap(outcome.backupPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath))
        // 메모리의 계정이 실제로 새 위치에 놓여야 한다 — 빈 폴더를 가리키면 안 된다.
        XCTAssertEqual(StorageService.inspectFile(at: target), .accounts(count: 1))
        XCTAssertEqual(service.accounts.first?.issuer, "CurrentService")
        XCTAssertNil(outcome.loadError)

        // inspectFile은 v1 평문과 v2 봉투를 구별하지 않고 같은 개수를 센다 — 이 자리에서
        // 실제로 평문 JSON을 썼던 회귀가 있었다(Task 5). 봉투 형식과 시크릿 부재를 직접 본다.
        let raw = try Data(contentsOf: URL(fileURLWithPath: target))
        guard case .v2 = try VaultCrypto.detect(raw) else {
            return XCTFail("새로 쓴 파일은 v2 봉투여야 한다")
        }
        XCTAssertFalse(String(data: raw, encoding: .utf8)!.contains("JBSWY3DPEHPK3PXP"),
                       "시크릿이 평문으로 남아 있으면 안 된다")
    }

    /// `save()`/`migrateToEncrypted()`는 새 키를 만들거나 새 봉투를 쓰기 전에 반드시
    /// `state`를 확인한다. `materializeCurrentAccounts`의 fallback 분기(현재 파일이 사라져
    /// 메모리의 accounts를 다시 봉인하는 경로)만 그 확인을 건너뛰고 있었다 — 잠긴 상태에서도
    /// `resolveKey()`가 조용히 새 Keychain 키를 만들고 빈 봉투를 새 위치에 써버렸다.
    func test_changePath_refusesToMintKeyWhenLockedAndCurrentFileIsGone() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        let target = "\(targetDir)/accounts.json"

        // 키가 있는 저장소로 먼저 v2 파일을 만든 뒤, 키를 모르는 새 KeyStore로 다시 연다 —
        // 파일은 있는데 키가 없는 "locked" 상태를 재현한다.
        let keyStoreWithKey = InMemoryKeyStore()
        let seed = makeService(path: tempPath, defaults: makeDefaults(), keyStore: keyStoreWithKey)
        try seed.load()
        try seed.add(sampleAccount())

        let lockedKeyStore = InMemoryKeyStore()
        let service = makeService(path: tempPath, defaults: defaults, keyStore: lockedKeyStore)
        try service.load()
        XCTAssertEqual(service.state, .locked)

        // 외부에서 현재 파일이 사라진 상황 — fallback 분기로 들어가는 조건.
        try FileManager.default.removeItem(atPath: tempPath)

        XCTAssertThrowsError(try service.changePath(to: target, strategy: .copyCurrent)) { error in
            guard case StorageError.vaultNotWritable = error else {
                return XCTFail("잠긴 상태에서 fallback 분기로 들어가면 vaultNotWritable을 던져야 한다: \(error)")
            }
        }

        XCTAssertNil(try lockedKeyStore.load(), "잠긴 상태에서 새 키를 만들면 안 된다")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target),
                       "쓰기가 거부됐다면 대상 파일이 생기면 안 된다")
        XCTAssertEqual(service.storagePath, tempPath, "거부됐다면 포인터도 옮기면 안 된다")
    }

    /// 복사가 실패하면 대상 폴더는 손도 대지 않은 상태여야 한다 — 백업부터 하면
    /// `.bak-*`만 남고 accounts.json이 사라져, 대상이 iCloud일 때 다른 Mac이 계정 0개가 된다.
    func test_changePath_copyFailureLeavesTargetIntact() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        let target = "\(targetDir)/accounts.json"
        try writeStorage(at: target, issuer: "TargetService")
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let service = makeService(path: tempPath, defaults: defaults)
        try service.load()

        // 대상 폴더를 읽기 전용으로 만들어 복사를 실패시킨다.
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: targetDir)
        addTeardownBlock {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: targetDir)
        }

        XCTAssertThrowsError(try service.changePath(to: target, strategy: .copyCurrent))

        // 대상 파일은 그대로, 백업도 임시 파일도 생기지 않았다.
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: targetDir), ["accounts.json"])
        XCTAssertEqual(StorageService.inspectFile(at: target), .accounts(count: 1))
        // 포인터도 옮겨가지 않았다.
        XCTAssertEqual(service.storagePath, tempPath)
    }

    /// 임시 파일을 만든 **뒤** 실패해도 그게 남으면 안 된다 — 내용이 평문 TOTP 시크릿이고,
    /// 대상이 iCloud면 아무도 정리하지 않는 채 영원히 동기화된다.
    ///
    /// 실패를 이 지점에 정확히 주입하려고 대상 파일에 immutable 플래그(`uchg`)를 건다.
    /// 디렉터리는 쓸 수 있으니 임시 파일 생성은 성공하고, 그다음 백업 rename만 EPERM으로
    /// 실패한다. 디렉터리 권한으로 막으면 생성 자체가 실패해 이 경로를 못 덮는다.
    func test_changePath_removesStagingFileWhenALaterStepFails() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        let target = "\(targetDir)/accounts.json"
        try writeStorage(at: target, issuer: "TargetService")
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let fm = FileManager.default
        try fm.setAttributes([.immutable: true], ofItemAtPath: target)
        addTeardownBlock {
            try? fm.setAttributes([.immutable: false], ofItemAtPath: target)
        }

        let service = makeService(path: tempPath, defaults: defaults)
        try service.load()

        XCTAssertThrowsError(try service.changePath(to: target, strategy: .copyCurrent))

        // 임시 파일도, 백업도 남지 않았고 대상 파일은 그대로다.
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: targetDir), ["accounts.json"])
        XCTAssertEqual(StorageService.inspectFile(at: target), .accounts(count: 1))
        XCTAssertEqual(service.storagePath, tempPath)
    }

    /// 성공 경로에서도 임시 파일이 남으면 안 된다.
    func test_changePath_leavesNoStagingFile() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let service = makeService(path: tempPath, defaults: defaults)
        try service.load()
        try service.changePath(to: "\(targetDir)/accounts.json", strategy: .copyCurrent)

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: targetDir), ["accounts.json"]
        )
    }

    /// 실질 위험은 "원본이 남는 것"이 아니라 그 순간부터 두 파일이 조용히 갈라진다는 것이다 —
    /// 버려진 iCloud 파일은 계속 동기화되어 다른 Mac은 갱신이 멈춘 옛 데이터를 계속 본다.
    func test_changePath_marksPreviousFileAsOld() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try writeStorage(at: tempPath, issuer: "CurrentService")

        let service = makeService(path: tempPath, defaults: defaults)
        try service.load()
        let outcome = try service.changePath(
            to: "\(targetDir)/accounts.json", strategy: .copyCurrent
        )

        XCTAssertNil(outcome.leftBehindPath)
        let marked = try XCTUnwrap(outcome.markedOldPath)
        XCTAssertEqual(try oldCopies(of: tempPath), [marked])
        XCTAssertEqual(outcome.leftBehindCount, 1)
        XCTAssertFalse(outcome.hasNotice, "예정대로 된 일은 알리지 않는다")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath))
        XCTAssertTrue(try storedIssuers(at: marked).contains("CurrentService"))
        // 새 위치는 멀쩡해야 한다.
        XCTAssertTrue(try storedIssuers(at: "\(targetDir)/accounts.json").contains("CurrentService"))
    }

    /// 대상 파일을 정본으로 삼는 경우에도 이전 위치는 낡은 사본이 된다.
    func test_changePath_adoptTarget_marksPreviousFileAsOld() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()
        try writeStorage(at: tempPath, issuer: "CurrentService")
        try writeStorage(at: "\(targetDir)/accounts.json", issuer: "TargetService")

        let service = makeService(path: tempPath, defaults: defaults)
        try service.load()
        let outcome = try service.changePath(
            to: "\(targetDir)/accounts.json", strategy: .adoptTarget
        )
        try service.migrateToEncrypted()

        let marked = try XCTUnwrap(outcome.markedOldPath)
        XCTAssertTrue(try storedIssuers(at: marked).contains("CurrentService"))
        XCTAssertEqual(service.accounts.map(\.issuer), ["TargetService"])
    }

    /// 이전 위치에 파일이 없으면 알릴 것도 없다.
    func test_changePath_noLeftBehindNoticeWhenNothingRemains() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()

        let service = makeService(path: tempPath, defaults: defaults)
        try service.load()
        let outcome = try service.changePath(
            to: "\(targetDir)/accounts.json", strategy: .copyCurrent
        )

        XCTAssertNil(outcome.leftBehindPath)
        XCTAssertNil(outcome.markedOldPath)
        XCTAssertFalse(outcome.hasNotice)
    }

    /// 이름만 바꾸고 제자리에 두면 최상위를 쓰던 사람에게는 평문 시크릿이 문서들 옆에 남는다.
    /// 표시된 파일도 그 위치의 `.qr2fa` 안으로 들어가야 한다.
    func test_markOld_movesFileIntoQr2faFolder() throws {
        let dir = makeTempDir()
        let path = "\(dir)/accounts.json"
        try writeStorage(at: path, issuer: "OldService")

        let marked = try XCTUnwrap(StorageService.markOldIfPresent(path))

        XCTAssertTrue(marked.hasPrefix("\(dir)/.qr2fa/accounts.json.old-"), marked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(try storedIssuers(at: marked).contains("OldService"))
    }

    /// 이미 데이터 폴더 안이면 옮길 곳이 없다 — `.qr2fa/.qr2fa`를 만들면 안 된다.
    func test_markOld_staysInPlaceWhenAlreadyInQr2faFolder() throws {
        let dir = "\(makeTempDir())/.qr2fa"
        try StorageService.createDirectory(dir)
        let path = "\(dir)/accounts.json"
        try writeStorage(at: path, issuer: "OldService")

        let marked = try XCTUnwrap(StorageService.markOldIfPresent(path))

        XCTAssertTrue(marked.hasPrefix("\(dir)/accounts.json.old-"), marked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(dir)/.qr2fa"))
    }

    // MARK: - Picked folder normalisation

    /// 사용자가 고른 폴더에는 항상 `.qr2fa`가 한 겹 붙는다 — 동기화 폴더 최상위에 평문
    /// 시크릿이 문서들 옆에 놓이는 걸 막는다.
    func test_dataDirectory_appendsQr2faToPickedFolder() {
        XCTAssertEqual(
            StorageService.dataDirectory(inside: "/Users/x/Library/Mobile Documents/com~apple~CloudDocs"),
            "/Users/x/Library/Mobile Documents/com~apple~CloudDocs/.qr2fa"
        )
    }

    /// 이미 데이터 폴더를 고른 사람에게 `.qr2fa/.qr2fa`를 만들면 안 된다.
    func test_dataDirectory_doesNotNestWhenAlreadyQr2fa() {
        XCTAssertEqual(
            StorageService.dataDirectory(inside: "/Users/x/Dropbox/.qr2fa"),
            "/Users/x/Dropbox/.qr2fa"
        )
        // 끝의 슬래시도 같은 폴더다.
        XCTAssertEqual(
            StorageService.dataDirectory(inside: "/Users/x/Dropbox/.qr2fa/"),
            "/Users/x/Dropbox/.qr2fa"
        )
    }

    /// 앱 전용 기본 폴더는 이미 자기 폴더라 한 겹 더 만들 이유가 없다(Go CLI 경로와도 어긋난다).
    func test_dataDirectory_keepsLocalDefaultAsIs() {
        let local = StorageService.localDefaultDirectory()
        XCTAssertEqual(StorageService.dataDirectory(inside: local), local)
    }

    // MARK: - Permissions

    private func permissions(of path: String) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        return try XCTUnwrap(attrs[.posixPermissions] as? NSNumber).intValue
    }

    /// 예전 버전으로 표시된 사본들의 전체 경로. 표시된 파일은 그 위치의 데이터 폴더 안으로 들어간다.
    private func oldCopies(of path: String) throws -> [String] {
        let url = URL(fileURLWithPath: path)
        let dir = StorageService.dataDirectory(inside: url.deletingLastPathComponent().path)
        let prefix = url.lastPathComponent + ".old-"
        guard FileManager.default.fileExists(atPath: dir) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { $0.hasPrefix(prefix) }
            .map { "\(dir)/\($0)" }
    }

    /// 저장 파일에 들어 있는 issuer 목록. 이름이 바뀐 파일의 내용이 살아 있는지 볼 때 쓴다.
    private func storedIssuers(at path: String) throws -> [String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let accounts = try XCTUnwrap(json["accounts"] as? [[String: Any]])
        return accounts.compactMap { $0["issuer"] as? String }
    }

    private func makeAccount(issuer: String = "GitHub") -> Account {
        Account(
            id: 0, name: "user", issuer: issuer,
            secret: "JBSWY3DPEHPK3PXP", tag: "",
            algorithm: "SHA1", digits: 6, period: 30, createdAt: Date()
        )
    }

    /// 내용이 평문 TOTP 시크릿이라 앱이 새로 만드는 파일은 소유자 전용이어야 한다.
    func test_save_createsOwnerOnlyFile() throws {
        let path = "\(makeTempDir())/fresh/accounts.json"
        let service = makeService(path: path, defaults: makeDefaults())
        try service.add(makeAccount())

        XCTAssertEqual(try permissions(of: path), 0o600)
    }

    /// 담는 디렉터리도 0700. 실제로 이 디렉터리를 만드는 건 StorageService.init이 띄우는
    /// FileWatcher라, save()만 고쳐서는 잡히지 않는 경로다.
    func test_save_createsOwnerOnlyDirectory() throws {
        let dir = "\(makeTempDir())/fresh"
        let service = makeService(path: "\(dir)/accounts.json", defaults: makeDefaults())
        try service.add(makeAccount())

        XCTAssertEqual(try permissions(of: dir), 0o700)
    }

    /// 저장 도중에도 느슨한 권한의 임시 파일이 남으면 안 된다.
    func test_save_leavesNoLooseTempFile() throws {
        let dir = "\(makeTempDir())/fresh"
        let path = "\(dir)/accounts.json"
        let service = makeService(path: path, defaults: makeDefaults())
        try service.add(makeAccount())

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir)
        XCTAssertEqual(leftovers, ["accounts.json"])
    }

    /// 이미 있는 파일의 권한은 앱이 바꾸지 않는다 — 사용자가 의도적으로 조정했을 수 있다.
    func test_save_keepsExistingFilePermissions() throws {
        let path = "\(makeTempDir())/accounts.json"
        XCTAssertTrue(FileManager.default.createFile(
            atPath: path, contents: Data("{}".utf8), attributes: [.posixPermissions: 0o644]
        ))

        let service = makeService(path: path, defaults: makeDefaults())
        try service.add(makeAccount())

        XCTAssertEqual(try permissions(of: path), 0o644)
    }

    /// 위치를 옮기며 만드는 사본도 새 파일이다 — 원본이 느슨했더라도 잠근다.
    func test_changePath_copyIsOwnerOnly() throws {
        let defaults = makeDefaults()
        let targetDir = "\(makeTempDir())/fresh"
        let target = "\(targetDir)/accounts.json"
        try writeStorage(at: tempPath, issuer: "CurrentService")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tempPath)

        let service = makeService(path: tempPath, defaults: defaults)
        try service.load()
        try service.changePath(to: target, strategy: .copyCurrent)

        XCTAssertEqual(try permissions(of: target), 0o600)
        XCTAssertEqual(try permissions(of: targetDir), 0o700)
    }

    func test_commitInitialLocation_createsOwnerOnlyDirectory() throws {
        let directory = "\(makeTempDir())/fresh"
        let service = makeService(path: tempPath, defaults: makeDefaults())
        try service.commitInitialLocation(directory: directory)

        XCTAssertEqual(try permissions(of: directory), 0o700)
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

    func test_inspectFileCountsV2WithoutKey() throws {
        let key = VaultCrypto.newKey()
        let inner = Data(#"{"version":"1.0","nextId":2,"accounts":[]}"#.utf8)
        let sealed = try VaultCrypto.seal(plaintext: inner, accountCount: 2, key: key)
        try sealed.write(to: URL(fileURLWithPath: tempPath))

        // 키를 주지 않는다 — 개수는 봉투 밖에서 읽혀야 한다
        XCTAssertEqual(StorageService.inspectFile(at: tempPath), .accounts(count: 2))
    }

    func test_inspectFileStillCountsV1() throws {
        let inner = Data(#"{"version":"1.0","nextId":1,"accounts":[{"id":1,"name":"u","issuer":"G","secret":"JBSWY3DPEHPK3PXP","tag":"","algorithm":"SHA1","digits":6,"period":30,"createdAt":"2026-01-01T00:00:00Z"}]}"#.utf8)
        try inner.write(to: URL(fileURLWithPath: tempPath))

        XCTAssertEqual(StorageService.inspectFile(at: tempPath), .accounts(count: 1))
    }

    func test_inspectFileUnreadableOnGarbage() throws {
        try Data("not json".utf8).write(to: URL(fileURLWithPath: tempPath))
        XCTAssertEqual(StorageService.inspectFile(at: tempPath), .unreadable)
    }
}

// MARK: - Reordering

extension StorageServiceTests {

    private func seeded(keyStore: KeyStore = InMemoryKeyStore()) throws -> StorageService {
        let service = makeService(path: tempPath, keyStore: keyStore)
        try service.load()
        for issuer in ["A", "B"] {
            try service.add(Account(
                id: 0, name: "user", issuer: issuer,
                secret: "JBSWY3DPEHPK3PXP", tag: "",
                algorithm: "SHA1", digits: 6, period: 30, createdAt: Date()
            ))
        }
        return service
    }

    func test_reorder_persistsTheNewOrder() throws {
        // 재오픈 서비스가 같은 키를 봐야 하므로 keyStore를 공유한다.
        let keyStore = InMemoryKeyStore()
        let service = try seeded(keyStore: keyStore)

        try service.reorder(to: service.accounts.reversed())
        XCTAssertEqual(service.accounts.map(\.issuer), ["B", "A"])

        let reloaded = makeService(path: tempPath, keyStore: keyStore)
        try reloaded.load()
        XCTAssertEqual(reloaded.accounts.map(\.issuer), ["B", "A"])
    }

    /// Reordering is not a delete path — the secrets are unrecoverable.
    func test_reorder_rejectsADroppedAccount() throws {
        let service = try seeded()

        XCTAssertThrowsError(try service.reorder(to: [service.accounts[0]]))
        XCTAssertEqual(service.accounts.map(\.issuer), ["A", "B"])
    }

    func test_reorder_rejectsADuplicatedAccount() throws {
        let service = try seeded()
        let duplicated = [service.accounts[0], service.accounts[0]]

        XCTAssertThrowsError(try service.reorder(to: duplicated))
        XCTAssertEqual(service.accounts.map(\.issuer), ["A", "B"])
    }
}
