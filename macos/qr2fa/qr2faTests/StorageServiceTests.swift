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

    /// 복원 후에도 온보딩이 다시 뜨면 안 된다.
    func test_resetToDefaultPath_keepsStoredChoice() throws {
        let defaults = makeDefaults()
        let targetDir = makeTempDir()

        let service = StorageService(path: tempPath, defaults: defaults)
        try service.commitInitialLocation(directory: targetDir)
        try service.resetToDefaultPath()

        XCTAssertFalse(service.needsLocationChoice)
        XCTAssertTrue(service.isDefaultPath)
    }
}
