import Foundation
import Observation

@Observable
final class StorageService {

    /// 사용자가 고른 저장 폴더의 절대 경로. 키가 없으면 아직 고르지 않은 것(= 온보딩 미완료).
    static let storageDirectoryKey = "storageDirectory"

    private(set) var accounts: [Account] = []
    private var nextId: Int = 0
    private(set) var storagePath: String
    private var fileWatcher: FileWatcher?
    private let defaults: UserDefaults

    init(path: String? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storagePath = path ?? StorageService.resolveDefaultPath(defaults: defaults)
        startFileWatcher()
    }

    private func startFileWatcher() {
        fileWatcher = FileWatcher(path: storagePath) { [weak self] in
            try? self?.load()
        }
    }

    // MARK: - Location choice

    /// 동기화를 쓰지 않을 때의 기본 폴더.
    static func localDefaultDirectory() -> String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.config/qr2fa"
    }

    /// iCloud Drive를 쓸 수 없는 Mac에서는 nil.
    static func iCloudDirectory() -> String? {
        let base = "\(FileManager.default.homeDirectoryForCurrentUser.path)"
            + "/Library/Mobile Documents/com~apple~CloudDocs"
        guard FileManager.default.fileExists(atPath: base) else { return nil }
        return "\(base)/.qr2fa"
    }

    /// 빈 문자열은 유효한 선택으로 보지 않는다 — 그대로 쓰면 루트에 쓰려다 실패한다.
    static func storedDirectory(defaults: UserDefaults) -> String? {
        let value = defaults.string(forKey: storageDirectoryKey) ?? ""
        return value.isEmpty ? nil : value
    }

    /// 저장된 선택이 있으면 그것, 없으면 로컬 기본값. iCloud Drive 존재 여부는 보지 않는다 —
    /// 예전엔 여기서 자동 추론을 했는데, iCloud를 나중에 켜면 경로가 조용히 바뀌면서
    /// 계정이 전부 사라진 것처럼 보이는 문제가 있었다.
    static func resolveDefaultPath(defaults: UserDefaults = .standard) -> String {
        let dir = storedDirectory(defaults: defaults) ?? localDefaultDirectory()
        return "\(dir)/accounts.json"
    }

    var needsLocationChoice: Bool {
        StorageService.storedDirectory(defaults: defaults) == nil
    }

    var isDefaultPath: Bool {
        storagePath == "\(StorageService.localDefaultDirectory())/accounts.json"
    }

    func resetToDefaultPath() throws {
        // 키를 지우지 않고 기본 폴더를 명시적으로 써 넣는다. 지우면 "기본값으로 복원"을
        // 눌렀을 뿐인데 다음 실행에 온보딩이 다시 뜬다.
        let dir = StorageService.localDefaultDirectory()
        defaults.set(dir, forKey: StorageService.storageDirectoryKey)
        storagePath = "\(dir)/accounts.json"
        startFileWatcher()
        try load()
    }

    // MARK: - Path change

    func changePath(to newPath: String) throws {
        let fm = FileManager.default
        let newDir = URL(fileURLWithPath: newPath).deletingLastPathComponent().path
        try fm.createDirectory(atPath: newDir, withIntermediateDirectories: true)

        if fm.fileExists(atPath: storagePath) {
            if fm.fileExists(atPath: newPath) {
                try fm.removeItem(atPath: newPath)
            }
            try fm.copyItem(atPath: storagePath, toPath: newPath)
        }

        defaults.set(newDir, forKey: StorageService.storageDirectoryKey)
        storagePath = newPath
        startFileWatcher()
        try load()
    }

    /// 온보딩에서 고른 위치를 확정한다.
    ///
    /// `changePath(to:)`와 달리 대상 파일을 절대 덮어쓰지 않는다. 온보딩 창을 닫고 계정을
    /// 추가한 뒤 다음 실행에서 iCloud를 고르는 경우, 복사 방식이면 iCloud에 있던 계정이
    /// 임시 파일로 덮여 날아간다.
    func commitInitialLocation(directory: String) throws {
        let fm = FileManager.default
        let target = "\(directory)/accounts.json"
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)

        // 대상이 비어 있을 때만 임시 파일을 옮긴다. 대상에 이미 파일이 있으면 그쪽이 정본.
        if !fm.fileExists(atPath: target),
           storagePath != target,
           fm.fileExists(atPath: storagePath) {
            try fm.moveItem(atPath: storagePath, toPath: target)
        }

        defaults.set(directory, forKey: StorageService.storageDirectoryKey)
        storagePath = target
        startFileWatcher()
        try load()
    }

    // MARK: - Load / Save

    func load() throws {
        guard FileManager.default.fileExists(atPath: storagePath) else {
            accounts = []
            nextId = 0
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: storagePath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeDateStrategy)
        let storage = try decoder.decode(AccountStorage.self, from: data)
        accounts = storage.accounts
        nextId = storage.nextId
    }

    private func save() throws {
        let storage = AccountStorage(version: "1.0", nextId: nextId, accounts: accounts)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(storage)

        let dir = URL(fileURLWithPath: storagePath).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let tempPath = storagePath + ".tmp"
        try data.write(to: URL(fileURLWithPath: tempPath))
        _ = try FileManager.default.replaceItemAt(
            URL(fileURLWithPath: storagePath),
            withItemAt: URL(fileURLWithPath: tempPath)
        )
    }

    // MARK: - CRUD

    func add(_ account: Account) throws {
        nextId += 1
        var acc = account
        acc.id = nextId
        acc.createdAt = Date()
        accounts.append(acc)
        try save()
    }

    func update(_ account: Account) throws {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw StorageError.accountNotFound
        }
        accounts[idx] = account
        try save()
    }

    func delete(id: Int) throws {
        accounts.removeAll { $0.id == id }
        try save()
    }

    // MARK: - Private helpers

    private static func decodeDateStrategy(_ decoder: Decoder) throws -> Date {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: s) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        if let d = fmt.date(from: s) { return d }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date: \(s)")
    }
}

enum StorageError: LocalizedError {
    case accountNotFound
    var errorDescription: String? { "Account not found" }
}
