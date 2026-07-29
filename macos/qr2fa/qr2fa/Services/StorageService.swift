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
    /// "기본 폴더"의 실체. 되돌리기가 이제 파일을 실제로 옮기므로, 테스트가 홈 디렉터리에
    /// 쓰지 않도록 갈아끼울 수 있어야 한다.
    let defaultDirectory: String

    init(
        path: String? = nil,
        defaults: UserDefaults = .standard,
        defaultDirectory: String = StorageService.localDefaultDirectory()
    ) {
        self.defaults = defaults
        self.defaultDirectory = defaultDirectory
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
    ///
    /// `defaults`에 기본값을 두지 않는다 — 테스트에서 인자를 빠뜨리면 조용히 실제
    /// UserDefaults 도메인을 읽어 통과/실패가 이 Mac의 상태에 좌우된다.
    static func resolveDefaultPath(defaults: UserDefaults) -> String {
        let dir = storedDirectory(defaults: defaults) ?? localDefaultDirectory()
        return "\(dir)/accounts.json"
    }

    var needsLocationChoice: Bool {
        StorageService.storedDirectory(defaults: defaults) == nil
    }

    var isDefaultPath: Bool {
        storagePath == "\(defaultDirectory)/accounts.json"
    }

    // MARK: - Path change

    /// 저장 위치를 옮길 때 어느 쪽 파일을 정본으로 삼을지.
    ///
    /// 여러 Mac에서 각자 온보딩을 마친 뒤 나중에 iCloud로 합류시키는 건 정상 사용 패턴이라,
    /// "대상에 이미 파일이 있는" 상황은 예외가 아니라 기본 시나리오로 다뤄야 한다.
    enum PathChangeStrategy {
        /// 지금 보고 있는 계정을 새 위치로 복사한다. 대상 파일은 지우지 않고 백업으로 밀어둔다.
        case copyCurrent
        /// 대상 폴더에 이미 있는 파일을 정본으로 삼는다. 현재 파일은 그대로 남는다.
        case adoptTarget
    }

    /// 대상 폴더의 계정 파일 상태. 덮어쓰기 전에 사용자에게 무엇을 물어야 할지 정하는 데 쓴다.
    enum TargetState: Equatable {
        case absent
        case accounts(count: Int)
        /// 파일은 있는데 읽을 수 없다(손상/권한). 덮어쓰기 전에 반드시 백업해야 한다.
        case unreadable
    }

    static func inspectTarget(directory: String) -> TargetState {
        inspectFile(at: "\(directory)/accounts.json")
    }

    static func inspectFile(at path: String) -> TargetState {
        guard FileManager.default.fileExists(atPath: path) else { return .absent }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom(decodeDateStrategy)
            let storage = try decoder.decode(AccountStorage.self, from: data)
            return .accounts(count: storage.accounts.count)
        } catch {
            return .unreadable
        }
    }

    /// 파일을 지우는 대신 `accounts.json.bak-<시각>`으로 옮긴다.
    ///
    /// 이 앱이 들고 있는 건 복구 불가능한 MFA 시크릿이라, 사용자가 덮어쓰기를 고른
    /// 경우에도 원본이 디스크에 남아 있어야 한다. 휴지통도 백업도 없이 unlink하면 끝이다.
    @discardableResult
    static func backupIfPresent(_ path: String) throws -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())

        // 같은 초에 두 번 눌러도 앞선 백업을 덮지 않도록 접미사를 붙여 빈자리를 찾는다.
        var candidate = "\(path).bak-\(stamp)"
        var suffix = 1
        while fm.fileExists(atPath: candidate) {
            candidate = "\(path).bak-\(stamp)-\(suffix)"
            suffix += 1
        }
        try fm.moveItem(atPath: path, toPath: candidate)
        return candidate
    }

    /// 저장 위치를 바꾼다. 어떤 전략이든 기존 파일을 지우지 않는다 — 덮어쓰기는 항상 백업을 남긴다.
    @discardableResult
    func changePath(to newPath: String, strategy: PathChangeStrategy) throws -> String? {
        let fm = FileManager.default
        let newDir = URL(fileURLWithPath: newPath).deletingLastPathComponent().path
        try fm.createDirectory(atPath: newDir, withIntermediateDirectories: true)

        var backupPath: String?
        // 같은 경로를 다시 고른 경우 복사는 무의미하고, 백업부터 하면 원본이 사라진다.
        if strategy == .copyCurrent, storagePath != newPath, fm.fileExists(atPath: storagePath) {
            backupPath = try StorageService.backupIfPresent(newPath)
            try fm.copyItem(atPath: storagePath, toPath: newPath)
        }

        defaults.set(newDir, forKey: StorageService.storageDirectoryKey)
        storagePath = newPath
        startFileWatcher()
        try load()
        return backupPath
    }

    /// 저장 위치를 기본 폴더로 되돌린다.
    ///
    /// 포인터만 옮기지 않고 `changePath`를 그대로 탄다. 예전엔 경로만 바꿔서, iCloud를 쓰던
    /// 사용자가 이 버튼을 누르면 빈 폴더를 가리키며 계정이 전부 사라진 것처럼 보였다 —
    /// 이 브랜치가 없애려던 바로 그 증상이다. UserDefaults 키는 지우지 않는다(지우면 다음
    /// 실행에 온보딩이 다시 뜬다) — `changePath`가 기본 폴더를 명시적으로 써 넣는다.
    @discardableResult
    func resetToDefaultPath(strategy: PathChangeStrategy) throws -> String? {
        try changePath(to: "\(defaultDirectory)/accounts.json", strategy: strategy)
    }

    /// 온보딩에서 고른 위치를 확정한다.
    ///
    /// `changePath(to:strategy:)`와 달리 대상 파일을 절대 덮어쓰지 않는다. 온보딩 창을 닫고 계정을
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
