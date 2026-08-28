import XCTest
@testable import qr2fa

final class KeyStoreTests: XCTestCase {

    func test_inMemoryStartsEmpty() throws {
        XCTAssertNil(try InMemoryKeyStore().load())
    }

    func test_inMemoryRoundTrip() throws {
        let store = InMemoryKeyStore()
        let key = VaultCrypto.newKey()
        try store.save(key)
        XCTAssertEqual(try store.load(), key)
    }

    func test_inMemorySeededWithKey() throws {
        let key = VaultCrypto.newKey()
        XCTAssertEqual(try InMemoryKeyStore(key: key).load(), key)
    }

    func test_inMemoryOverwrites() throws {
        let store = InMemoryKeyStore(key: VaultCrypto.newKey())
        let replacement = VaultCrypto.newKey()
        try store.save(replacement)
        XCTAssertEqual(try store.load(), replacement)
    }
}
