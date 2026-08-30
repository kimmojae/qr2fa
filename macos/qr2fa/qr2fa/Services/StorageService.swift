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

    /// 저장 파일을 읽을 수 있는 상태인지.
    ///
    /// 지금까지는 "파일이 없으면 빈 목록, 그 외엔 항상 읽힘"이었다. 암호화 후에는
    /// **파일은 멀쩡한데 키가 없는** 상태가 생기고, 이걸 빈 목록과 구별하지 못하면
    /// 그 위에 저장하는 순간 파일이 실제로 비워진다.
    enum VaultState: Equatable {
        case unlocked
        case locked                  // 파일은 있는데 키가 없다
        case needsMigration          // v1 평문 파일이 있다
        case unreadable(String)      // 손상, 모르는 version, 복호화 실패
    }

    private(set) var state: VaultState = .unlocked
    private let keyStore: KeyStore

    init(
        path: String? = nil,
        defaults: UserDefaults = .standard,
        defaultDirectory: String = StorageService.localDefaultDirectory(),
        keyStore: KeyStore = KeychainKeyStore()
    ) {
        self.defaults = defaults
        self.defaultDirectory = defaultDirectory
        self.keyStore = keyStore
        self.storagePath = path ?? StorageService.resolveDefaultPath(defaults: defaults)
        startFileWatcher()
    }

    private func startFileWatcher() {
        fileWatcher = FileWatcher(path: storagePath) { [weak self] in
            guard let self else { return }
            do {
                try self.load()
            } catch {
                // 외부 변경을 읽지 못했다. 조용히 빈 화면이 되면 계정이 사라진 것처럼 보인다.
                self.accounts = []
                self.state = .unreadable(error.localizedDescription)
            }
        }
    }

    // MARK: - Location choice

    /// 동기화를 쓰지 않을 때의 기본 폴더.
    static func localDefaultDirectory() -> String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.config/qr2fa"
    }

    /// 데이터 폴더 이름. 사용자가 어떤 폴더를 고르든 이 이름의 하위 폴더에 넣는다.
    static let dataDirectoryName = ".qr2fa"

    /// 사용자가 패널에서 고른 폴더 안의 실제 데이터 폴더.
    ///
    /// 고른 폴더에 `accounts.json`을 그대로 놓으면 iCloud Drive나 Dropbox 최상위를 골랐을 때
    /// 평문 TOTP 시크릿이 문서들 옆에 놓인다. 하위 폴더를 만드는 건 사용자가 아니라 앱이 할 일이다.
    ///
    /// 이미 데이터 폴더를 고른 경우(`.qr2fa`로 끝남)와 앱 전용 기본 폴더는 그대로 둔다 —
    /// 전자는 `.qr2fa/.qr2fa`가 되고, 후자는 Go CLI가 읽는 `~/.config/qr2fa/accounts.json`과
    /// 어긋난다.
    static func dataDirectory(inside picked: String) -> String {
        let trimmed = picked.hasSuffix("/") ? String(picked.dropLast()) : picked
        if trimmed == localDefaultDirectory() { return trimmed }
        if URL(fileURLWithPath: trimmed).lastPathComponent == dataDirectoryName { return trimmed }
        return "\(trimmed)/\(dataDirectoryName)"
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
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let format = try? VaultCrypto.detect(data) else { return .unreadable }

        switch format {
        case .v2(let envelope):
            // 키 없이 센다. accountCount가 봉투 밖에 있는 이유다.
            return .accounts(count: envelope.accountCount)
        case .v1Plaintext:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom(decodeDateStrategy)
            guard let storage = try? decoder.decode(AccountStorage.self, from: data) else {
                return .unreadable
            }
            return .accounts(count: storage.accounts.count)
        }
    }

    /// 파일을 지우는 대신 `accounts.json.bak-<시각>`으로 옮긴다.
    ///
    /// 이 앱이 들고 있는 건 복구 불가능한 MFA 시크릿이라, 사용자가 덮어쓰기를 고른
    /// 경우에도 원본이 디스크에 남아 있어야 한다. 휴지통도 백업도 없이 unlink하면 끝이다.
    @discardableResult
    static func backupIfPresent(_ path: String) throws -> String? {
        try renameAside(path, as: path, kind: "bak")
    }

    /// 이전 위치에 남은 계정 파일을 그 위치의 데이터 폴더 안으로 넣고 `.old-<시각>`을 붙인다.
    ///
    /// 이름만 바꾸고 제자리에 두면, 최상위 폴더를 쓰던 사람에게는 평문 시크릿이 계속 문서들
    /// 옆에 남는다. 앱이 만든 파일은 전부 `.qr2fa` 안에 있어야 정리도 한 곳에서 끝난다.
    /// 같은 이름으로 남겨 두면 어느 쪽이 정본인지 파일만 봐서는 알 수 없고, 그 폴더가 iCloud면
    /// 갱신이 멈춘 파일이 계속 동기화된다. 지우지는 않는다 — 내용이 복구 불가능한 시크릿이다.
    @discardableResult
    static func markOldIfPresent(_ path: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        let currentDir = url.deletingLastPathComponent().path
        let dataDir = dataDirectory(inside: currentDir)
        if dataDir != currentDir { try createDirectory(dataDir) }
        return try renameAside(path, as: "\(dataDir)/\(url.lastPathComponent)", kind: "old")
    }

    /// `path`의 파일을 `<base>.<kind>-<시각>`으로 옮긴다. 없으면 nil.
    private static func renameAside(_ path: String, as base: String, kind: String) throws -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())

        // 같은 초에 두 번 눌러도 앞선 파일을 덮지 않도록 접미사를 붙여 빈자리를 찾는다.
        var candidate = "\(base).\(kind)-\(stamp)"
        var suffix = 1
        while fm.fileExists(atPath: candidate) {
            candidate = "\(base).\(kind)-\(stamp)-\(suffix)"
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
        /// 이전 위치의 계정 파일을 `.old-<시각>`으로 바꿔 둔 경로.
        ///
        /// 이 순간부터 두 파일이 조용히 갈라지므로(버려진 iCloud 파일은 계속 동기화된다)
        /// 이름으로 예전 버전임을 드러낸다. 이전 경로를 아직 보고 있는 다른 Mac은 계정이
        /// 0개로 보이게 되는데, 갱신이 멈춘 데이터를 계속 보여주는 것보다 낫다고 판단했다.
        var markedOldPath: String?
        /// 이름을 바꾸지 못해 이전 위치에 그대로 남은 계정 파일.
        var leftBehindPath: String?
        var leftBehindCount: Int = 0

        /// 사용자를 멈춰 세울 만한 일이 있었는가.
        ///
        /// 성공적인 변경은 알리지 않는다 — 경로 줄이 바뀐 것 자체가 피드백이고, 백업과
        /// "예전 버전으로 표시"는 그렇게 하겠다고 이미 말한 대로 된 것뿐이다. 예정대로
        /// 되지 않은 것(이름을 못 바꿔 낡은 사본이 그대로 남음, 새 위치를 못 읽음)만 알린다.
        var hasNotice: Bool { loadError != nil || leftBehindPath != nil }
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

        // 어느 전략이든 이전 위치의 파일은 지우지 않는다(복사지 이사가 아니다). 대신 예전
        // 버전임이 이름에 드러나게 바꾼다. 포인터를 옮긴 뒤에는 previousPath를 다시 볼 수
        // 없으므로 여기서 처리한다.
        if previousPath != newPath,
           case .accounts(let count) = StorageService.inspectFile(at: previousPath), count > 0 {
            outcome.leftBehindCount = count
            do {
                outcome.markedOldPath = try StorageService.markOldIfPresent(previousPath)
            } catch {
                // 위치 변경은 이미 끝났다. 이름을 못 바꿨다고 되돌리면 오히려 상태가 꼬이므로
                // "그대로 남아 있다"고 알리는 데서 그친다.
                outcome.leftBehindPath = previousPath
            }
        }

        defaults.set(newDir, forKey: StorageService.storageDirectoryKey)
        storagePath = newPath
        startFileWatcher()
        do {
            try load()
        } catch {
            outcome.loadError = error
        }
        outcome.loadError = outcome.loadError ?? loadErrorFromUnreadableState()
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
            // 새로 쓰는 파일이니 평문으로 남기지 않는다 — save()와 같은 봉투로 감싼다.
            // resolveKey()가 새 Keychain 키를 만들 수도 있으므로, save()/migrateToEncrypted()와
            // 같은 잣대로 여기서도 확인한다 — 그러지 않으면 잠긴 상태에서도 조용히 새 키와
            // 빈 봉투가 생긴다. 파일이 있어 그대로 복사하는 위 분기는 아무것도 새로 만들지
            // 않으므로 이 확인이 필요 없다.
            try requireUnlocked()
            let plaintext = try encodedSnapshot()
            let key = try resolveKey()
            let sealed = try VaultCrypto.seal(plaintext: plaintext, accountCount: accounts.count, key: key)
            try StorageService.writeLocked(sealed, to: staging)
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
        /// 대상에 이미 파일이 있어 옮기지 못한 임시 파일을 `.old-<시각>`으로 바꿔 둔 경로.
        var markedOldPath: String?
        /// 이름을 바꾸지 못해 이전 위치에 그대로 남은 계정 파일.
        var leftBehindPath: String?
        var leftBehindCount: Int = 0

        /// 성공적인 확정은 알리지 않는다 — `PathChangeOutcome.hasNotice`와 같은 기준이다.
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
                outcome.leftBehindCount = count
                do {
                    outcome.markedOldPath = try StorageService.markOldIfPresent(storagePath)
                } catch {
                    outcome.leftBehindPath = storagePath
                }
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
        outcome.loadError = outcome.loadError ?? loadErrorFromUnreadableState()
        return outcome
    }

    // MARK: - Load / Save

    func load() throws {
        guard FileManager.default.fileExists(atPath: storagePath) else {
            accounts = []
            nextId = 0
            state = .unlocked
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: storagePath))

        let format: VaultCrypto.Format
        do {
            format = try VaultCrypto.detect(data)
        } catch {
            // 읽지 못한 파일은 건드리지 않는다. 던지지 않고 상태로 알린다 —
            // 호출부가 "빈 계정"과 구별할 수 있어야 한다.
            accounts = []
            state = .unreadable(error.localizedDescription)
            return
        }

        switch format {
        case .v1Plaintext:
            // 계정을 아직 싣지 않는다. migrateToEncrypted()가 부를 때까지 기다린다.
            accounts = []
            state = .needsMigration

        case .v2(let envelope):
            guard let key = try keyStore.load() else {
                accounts = []
                state = .locked
                return
            }
            do {
                let plaintext = try VaultCrypto.open(envelope, key: key)
                let storage = try Self.decodeStorage(plaintext)
                accounts = storage.accounts
                nextId = storage.nextId
                state = .unlocked
            } catch {
                accounts = []
                state = .unreadable(error.localizedDescription)
            }
        }
    }

    /// 봉투 안의 JSON을 지금까지와 똑같이 디코딩한다.
    private static func decodeStorage(_ data: Data) throws -> AccountStorage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeDateStrategy)
        return try decoder.decode(AccountStorage.self, from: data)
    }

    /// `load()`는 읽지 못한 파일을 던지지 않고 `state`로만 알린다. `commitInitialLocation`/
    /// `changePath`는 여전히 "위치는 이미 바뀌었는데 새 파일을 못 읽었다"를 `outcome.loadError`로
    /// 알려야 하므로, `load()` 호출 뒤 이 상태를 확인해 그 계약을 이어준다.
    private func loadErrorFromUnreadableState() -> Error? {
        guard case .unreadable(let message) = state else { return nil }
        return VaultUnreadableError(message: message)
    }

    /// 메모리의 계정을 디스크 포맷으로 직렬화한다.
    private func encodedSnapshot() throws -> Data {
        let storage = AccountStorage(version: "1.0", nextId: nextId, accounts: accounts)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        return try encoder.encode(storage)
    }

    /// 잠기거나 읽지 못한 상태에서 쓰기를 막는다. 계정을 바꾸는 모든 진입점(`save()`와
    /// CRUD 메서드들)이 메모리를 건드리기 전에 이걸 먼저 호출해야 한다 — `save()` 안에서만
    /// 확인하면 CRUD 메서드가 이미 `accounts`를 바꾼 뒤라 디스크와 메모리가 어긋난다.
    private func requireUnlocked() throws {
        guard state == .unlocked else { throw StorageError.vaultNotWritable }
    }

    private func save() throws {
        try requireUnlocked()

        let plaintext = try encodedSnapshot()
        let key = try resolveKey()
        let data = try VaultCrypto.seal(plaintext: plaintext, accountCount: accounts.count, key: key)

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

    /// 키를 꺼내오고, 없으면 새로 만들어 보관한다(첫 실행 경로).
    private func resolveKey() throws -> Data {
        if let existing = try keyStore.load() { return existing }
        let fresh = VaultCrypto.newKey()
        try keyStore.save(fresh)
        return fresh
    }

    /// v1 평문 파일을 v2 봉투로 옮긴다. 반환값은 밀려난 평문 원본의 경로(없으면 nil) —
    /// 마이그레이션 안내에서 "여기 남겨뒀습니다"로 쓴다.
    ///
    /// 순서가 핵심이다 — 평문 원본과 v2는 **같은 경로**를 쓴다. v2를 먼저 쓰면
    /// 그 순간 평문 원본이 사라진다. 임시 파일에 먼저 쓰고, 원본을 `.old-`로 밀고,
    /// 마지막에 임시를 제자리로 올린다.
    @discardableResult
    func migrateToEncrypted() throws -> String? {
        guard state == .needsMigration else { return nil }

        let data = try Data(contentsOf: URL(fileURLWithPath: storagePath))
        let storage = try Self.decodeStorage(data)

        let key = try resolveKey()
        let sealed = try VaultCrypto.seal(
            plaintext: data,
            accountCount: storage.accounts.count,
            key: key
        )

        let staging = storagePath + ".migrating-\(UUID().uuidString.prefix(8))"
        defer { try? FileManager.default.removeItem(atPath: staging) }
        try StorageService.writeLocked(sealed, to: staging)

        let backupPath = try StorageService.markOldIfPresent(storagePath)
        try FileManager.default.moveItem(atPath: staging, toPath: storagePath)

        accounts = storage.accounts
        nextId = storage.nextId
        state = .unlocked
        return backupPath
    }

    // MARK: - CRUD

    @discardableResult
    func add(_ account: Account) throws -> Account {
        try requireUnlocked()
        nextId += 1
        var acc = account
        acc.id = nextId
        acc.createdAt = Date()
        accounts.append(acc)
        try save()
        return acc
    }

    func update(_ account: Account) throws {
        try requireUnlocked()
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw StorageError.accountNotFound
        }
        accounts[idx] = account
        try save()
    }

    func delete(id: Int) throws {
        try requireUnlocked()
        accounts.removeAll { $0.id == id }
        try save()
    }

    /// Replaces the stored order. Rejects anything that is not a pure permutation —
    /// reordering must never be a path that loses or duplicates an account, because
    /// the payload is unrecoverable TOTP secrets.
    func reorder(to reordered: [Account]) throws {
        try requireUnlocked()
        guard reordered.count == accounts.count,
              Set(reordered.map(\.id)) == Set(accounts.map(\.id)) else {
            throw StorageError.notAReordering
        }
        accounts = reordered
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
    case notAReordering
    case vaultNotWritable

    var errorDescription: String? {
        switch self {
        case .accountNotFound: "Account not found"
        case .notAReordering: "Reordering must keep every account exactly once"
        case .vaultNotWritable: "Cannot save while the accounts file is unreadable"
        }
    }
}

/// `load()`가 `state = .unreadable(message)`로만 알리는 실패를, `outcome.loadError`처럼
/// 여전히 `Error`를 기대하는 호출부로 옮길 때 그 메시지를 그대로 담아 보낸다.
struct VaultUnreadableError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
