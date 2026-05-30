import Foundation
import Observation

@Observable
final class StorageService {

    private(set) var accounts: [Account] = []
    private var nextId: Int = 0
    let storagePath: String

    init(path: String? = nil) {
        self.storagePath = path ?? StorageService.resolveDefaultPath()
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

    // MARK: - Path resolution (mirrors Go CLI priority)

    static func resolveDefaultPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // 1. Config file: ~/.config/qr2fa/config.json → data_dir
        let configPath = "\(home)/.config/qr2fa/config.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let config = try? JSONDecoder().decode(CLIConfig.self, from: data),
           !config.dataDir.isEmpty {
            return "\(config.dataDir)/accounts.json"
        }

        // 2. iCloud Drive
        let iCloud = "\(home)/Library/Mobile Documents/com~apple~CloudDocs"
        if FileManager.default.fileExists(atPath: iCloud) {
            return "\(iCloud)/.qr2fa/accounts.json"
        }

        // 3. Home directory fallback
        return "\(home)/.qr2fa/accounts.json"
    }

    // MARK: - Private helpers

    private struct CLIConfig: Codable {
        let dataDir: String
        enum CodingKeys: String, CodingKey { case dataDir = "data_dir" }
    }

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
