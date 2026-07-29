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

    // MARK: - Permissions

    /// 이 앱이 새로 만드는 저장 파일/디렉터리의 권한. 내용이 평문 TOTP 시크릿이라 소유자
    /// 전용이어야 한다. Go CLI(`cli/internal/storage/storage.go`)도 0600/0700을 쓴다 —
    /// 두 앱이 같은 파일을 공유하므로 값을 맞춰 둔다.
    static let filePermissions = 0o600
    static let directoryPermissions = 0o700

    /// 새로 만드는 디렉터리는 0700으로. 이미 있는 디렉터리에는 attributes가 적용되지 않으므로
    /// 사용자가 조정해 둔 권한을 덮어쓰지 않는다.
    static func createDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions]
        )
    }

    /// 새로 만든 항목을 소유자 전용으로 잠근다.
    ///
    /// 실패를 무시하는 건 의도적이다 — iCloud Drive처럼 POSIX 권한을 그대로 유지하지 않는
    /// 위치가 있는데, 권한을 못 걸었다고 저장 자체가 실패하면 안 된다(best-effort).
    static func restrictPermissions(_ path: String, to mode: Int) {
        try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    }

    /// 새 파일을 0600으로 만든 뒤 거기에 쓴다.
    ///
    /// `Data.write(to:)`는 권한을 지정할 수 없어서 그냥 쓰면 umask대로(보통 0644) 만들어지고,
    /// 그사이 시크릿이 느슨한 권한으로 디스크에 존재하는 창이 생긴다. 빈 파일을 먼저 잠가
    /// 두고 비원자적으로 덮어쓰면 inode와 권한이 유지되므로 그 창이 없다.
    private static func writeLocked(_ data: Data, to path: String) throws {
        let createdLocked = FileManager.default.createFile(
            atPath: path,
            contents: nil,
            attributes: [.posixPermissions: filePermissions]
        )
        try data.write(to: URL(fileURLWithPath: path))
        if !createdLocked {
            // 권한을 지정해 만들지 못한 경우(권한을 지원하지 않는 파일시스템 등)라도
            // 뒤늦게나마 잠가 본다. 실패해도 쓰기 자체는 이미 끝났다.
            restrictPermissions(path, to: filePermissions)
        }
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

    /// `changePath`의 결과. 위치 변경은 성공했지만 사용자에게 알려야 할 게 남은 경우를 담는다.
    struct PathChangeOutcome {
        /// 덮어쓰기로 밀려난 대상 파일의 백업 경로.
        var backupPath: String?
        /// 위치는 이미 바뀌었는데 새 위치의 파일을 읽지 못했다.
        var loadError: Error?
        /// 이전 위치에 그대로 남은 계정 파일. 지우지 않는 건 의도지만, 이 순간부터 두 파일이
        /// 조용히 갈라지므로(버려진 iCloud 파일은 계속 동기화된다) 반드시 알려야 한다.
        var leftBehindPath: String?
        var leftBehindCount: Int = 0

        var hasNotice: Bool {
            backupPath != nil || loadError != nil || leftBehindPath != nil
        }
    }

    /// 저장 위치를 바꾼다. 어떤 전략이든 기존 파일을 지우지 않는다 — 덮어쓰기는 항상 백업을 남긴다.
    ///
    /// 던지는 건 "위치를 바꾸지 못한" 경우뿐이다. 위치를 바꾼 뒤의 로드 실패는
    /// `PathChangeOutcome.loadError`로 돌려준다 — 던지면 변경은 이미 영속화됐는데 뷰는
    /// "바꿀 수 없습니다"를 띄우고, `accounts`는 옛 내용 그대로 남아 모델이 어긋난다.
    @discardableResult
    func changePath(to newPath: String, strategy: PathChangeStrategy) throws -> PathChangeOutcome {
        let previousPath = storagePath
        let newDir = URL(fileURLWithPath: newPath).deletingLastPathComponent().path
        try StorageService.createDirectory(newDir)

        var outcome = PathChangeOutcome()

        // 같은 경로를 다시 고른 경우 복사는 무의미하고, 백업부터 하면 원본이 사라진다.
        if strategy == .copyCurrent, previousPath != newPath {
            outcome.backupPath = try materializeCurrentAccounts(at: newPath)
        }

        // 어느 전략이든 이전 위치의 파일은 남긴다(복사지 이사가 아니다). 남았다는 사실을
        // 여기서 확인해 둔다 — 포인터를 옮긴 뒤에는 previousPath를 다시 볼 수 없다.
        if previousPath != newPath,
           case .accounts(let count) = StorageService.inspectFile(at: previousPath), count > 0 {
            outcome.leftBehindPath = previousPath
            outcome.leftBehindCount = count
        }

        defaults.set(newDir, forKey: StorageService.storageDirectoryKey)
        storagePath = newPath
        startFileWatcher()
        do {
            try load()
        } catch {
            outcome.loadError = error
        }
        return outcome
    }

    /// 현재 계정을 대상 위치에 놓는다. 반환값은 밀려난 기존 파일의 백업 경로(없으면 nil).
    ///
    /// 순서가 핵심이다 — 임시 이름으로 **먼저** 만들고, 그게 성공한 뒤에야 기존 파일을 백업으로
    /// 밀고, 마지막에 임시를 최종 이름으로 올린다. 어느 단계에서 실패해도 대상 폴더에는 항상
    /// 살아 있는 `accounts.json`이 남는다. 백업부터 하면 복사가 실패했을 때 대상에 `.bak-*`만
    /// 남는데, 대상이 iCloud면 다른 Mac의 FileWatcher가 그 삭제를 보고 즉시 계정 0개가 된다.
    private func materializeCurrentAccounts(at newPath: String) throws -> String? {
        let fm = FileManager.default
        let staging = "\(newPath).incoming-\(UUID().uuidString.prefix(8))"
        // 임시 파일 내용은 평문 TOTP 시크릿이다. 쓰기 도중에 실패하면(디스크 풀, 중단)
        // 부분적으로 쓰인 파일이 남고, 대상이 iCloud면 그게 영원히 동기화된다. 경로를
        // 정한 시점에 정리를 예약해 어느 경로로 빠져나가든 남지 않게 한다. 성공 경로에서는
        // 이미 최종 이름으로 rename된 뒤라 지울 게 없다.
        defer { try? fm.removeItem(atPath: staging) }

        if fm.fileExists(atPath: storagePath) {
            try fm.copyItem(atPath: storagePath, toPath: staging)
            // copyItem은 원본 권한을 그대로 가져온다. 새로 만들어진 파일이므로,
            // 원본이 느슨했더라도 여기서 잠근다.
            StorageService.restrictPermissions(staging, to: StorageService.filePermissions)
        } else {
            // 현재 파일이 외부에서 사라졌어도 메모리의 계정은 살아 있다. "현재 계정으로
            // 덮어쓰기"를 고른 사용자에게는 그 계정이 실제로 새 위치에 놓여야 한다.
            try StorageService.writeLocked(try encodedSnapshot(), to: staging)
        }

        var backupPath: String?
        do {
            backupPath = try StorageService.backupIfPresent(newPath)
            try fm.moveItem(atPath: staging, toPath: newPath)
        } catch {
            // 백업까지 마치고 마지막 rename에서 실패하면 대상에 살아 있는 파일이 없다.
            // 백업을 제자리로 되돌려 놓고 던진다.
            if let backupPath, !fm.fileExists(atPath: newPath) {
                try? fm.moveItem(atPath: backupPath, toPath: newPath)
            }
            throw error
        }
        return backupPath
    }

    // MARK: - Initial location commit

    /// `commitInitialLocation`의 결과. 위치 확정은 성공했지만 사용자에게 알려야 할 게 남은 경우를 담는다.
    struct CommitOutcome {
        /// 확정한 위치의 파일을 읽지 못했다. 위치는 이미 고정됐으므로 재시도는 의미가 없다.
        var loadError: Error?
        /// 대상에 이미 파일이 있어 옮기지 못하고 남겨둔 이전 위치.
        var leftBehindPath: String?
        var leftBehindCount: Int = 0

        var hasNotice: Bool { loadError != nil || leftBehindPath != nil }
    }

    /// 온보딩에서 고른 위치를 확정한다.
    ///
    /// `changePath(to:strategy:)`와 달리 대상 파일을 절대 덮어쓰지 않는다. 온보딩 창을 닫고 계정을
    /// 추가한 뒤 다음 실행에서 iCloud를 고르는 경우, 복사 방식이면 iCloud에 있던 계정이
    /// 임시 파일로 덮여 날아간다.
    ///
    /// 던지는 건 "위치 고정 자체가 실패한" 경우뿐이다. 위치를 고정한 뒤의 로드 실패는
    /// `CommitOutcome.loadError`로 돌려준다 — 선택은 이미 영속화됐으므로 호출 측은 경고만
    /// 띄우고 온보딩을 닫아야 한다. 던지면 사용자가 같은 예외를 무한 반복하며 갇힌다.
    @discardableResult
    func commitInitialLocation(directory: String) throws -> CommitOutcome {
        let fm = FileManager.default
        let target = "\(directory)/accounts.json"
        try StorageService.createDirectory(directory)

        var outcome = CommitOutcome()
        let targetExists = fm.fileExists(atPath: target)
        let provisionalExists = storagePath != target && fm.fileExists(atPath: storagePath)

        if !targetExists, provisionalExists {
            // 대상이 비어 있을 때만 임시 파일을 옮긴다.
            try fm.moveItem(atPath: storagePath, toPath: target)
        } else if targetExists, provisionalExists {
            // 대상에 이미 파일이 있으면 그쪽이 정본이고 임시 파일은 그대로 남는다. 소실은
            // 아니지만 그 계정들이 UI에서 사라지므로 조용히 넘어가면 안 된다.
            if case .accounts(let count) = StorageService.inspectFile(at: storagePath), count > 0 {
                outcome.leftBehindPath = storagePath
                outcome.leftBehindCount = count
            }
        }

        defaults.set(directory, forKey: StorageService.storageDirectoryKey)
        storagePath = target
        startFileWatcher()
        do {
            try load()
        } catch {
            outcome.loadError = error
        }
        return outcome
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

    /// 메모리의 계정을 디스크 포맷으로 직렬화한다.
    private func encodedSnapshot() throws -> Data {
        let storage = AccountStorage(version: "1.0", nextId: nextId, accounts: accounts)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        return try encoder.encode(storage)
    }

    private func save() throws {
        let data = try encodedSnapshot()

        let dir = URL(fileURLWithPath: storagePath).deletingLastPathComponent().path
        try StorageService.createDirectory(dir)

        let tempPath = storagePath + ".tmp"
        try StorageService.writeLocked(data, to: tempPath)

        // replaceItemAt은 대상이 이미 있으면 그 파일의 권한을 보존한다 — 사용자가 의도적으로
        // 조정했을 수 있으므로 앱이 임의로 바꾸지 않는다. 대상이 없을 때만 임시 파일의
        // 0600이 그대로 새 파일의 권한이 된다.
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
