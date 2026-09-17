import XCTest
@testable import qr2fa

final class CachingKeyStoreTests: XCTestCase {

    /// 조회 횟수를 세는 가짜 저장소. 실제 Keychain은 이 맥의 상태에 결과가 좌우되므로 쓰지 않는다.
    private final class CountingKeyStore: KeyStore {
        var stored: Data?
        private(set) var loadCount = 0
        private(set) var saveCount = 0

        init(stored: Data? = nil) { self.stored = stored }

        func load() throws -> Data? {
            loadCount += 1
            return stored
        }

        func save(_ key: Data) throws {
            saveCount += 1
            stored = key
        }
    }

    private let key = Data(repeating: 0xAB, count: 32)

    func test_repeatedLoadsHitTheKeychainOnce() throws {
        let inner = CountingKeyStore(stored: key)
        let caching = CachingKeyStore(inner)

        for _ in 0..<5 {
            XCTAssertEqual(try caching.load(), key)
        }

        XCTAssertEqual(inner.loadCount, 1)
    }

    /// 저장은 그대로 내려보내되, 이어지는 조회는 캐시가 받아낸다.
    func test_saveUpdatesTheCacheWithoutAnotherLoad() throws {
        let inner = CountingKeyStore()
        let caching = CachingKeyStore(inner)

        try caching.save(key)

        XCTAssertEqual(try caching.load(), key)
        XCTAssertEqual(inner.saveCount, 1)
        XCTAssertEqual(inner.loadCount, 0)
    }

    /// 키가 없거나 접근이 거부된 경우는 캐시하지 않는다 — 나중에 허용하면 같은 실행에서 열려야 한다.
    func test_missingKeyIsNotCached() throws {
        let inner = CountingKeyStore(stored: nil)
        let caching = CachingKeyStore(inner)

        XCTAssertNil(try caching.load())
        inner.stored = key

        XCTAssertEqual(try caching.load(), key)
        XCTAssertEqual(inner.loadCount, 2)
    }
}
