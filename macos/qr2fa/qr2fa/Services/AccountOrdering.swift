import Foundation

/// Account order *is* the order in `accounts.json`'s array — there is no sort key.
///
/// A stored field would not survive a round trip through the Go CLI (it drops fields
/// it does not know when it writes the file back), whereas the array order does.
enum AccountOrdering {

    /// The services, in the order the array first mentions them.
    static func issuers(in accounts: [Account]) -> [String] {
        var seen = Set<String>()
        return accounts.map(\.displayIssuer).filter { seen.insert($0).inserted }
    }

    /// The array after moving the services at `source` (offsets into `issuers(in:)`)
    /// to `destination`, using the same offset convention as SwiftUI's `onMove`.
    ///
    /// A service moves as a whole block, so this gathers every service into a
    /// contiguous run — accounts added in mixed order start out interleaved.
    static func movingIssuers(in accounts: [Account], from source: IndexSet, to destination: Int) -> [Account] {
        var blocks = issuers(in: accounts).map { issuer in
            accounts.filter { $0.displayIssuer == issuer }
        }
        move(&blocks, from: source, to: destination)
        return blocks.flatMap { $0 }
    }

    /// The array after moving accounts *within one service*. `source` and `destination`
    /// are offsets into that service's filtered list, not into the whole array.
    ///
    /// The service's accounts keep the array slots they already occupy, so services that
    /// are interleaved with it do not shift.
    static func movingAccounts(in accounts: [Account], issuer: String, from source: IndexSet, to destination: Int) -> [Account] {
        let slots = accounts.indices.filter { accounts[$0].displayIssuer == issuer }
        var group = slots.map { accounts[$0] }
        move(&group, from: source, to: destination)

        var reordered = accounts
        for (slot, account) in zip(slots, group) {
            reordered[slot] = account
        }
        return reordered
    }

    /// `onMove` semantics: `destination` is an offset into the array *before* the
    /// moved elements are lifted out, and the elements land in front of it.
    private static func move<T>(_ items: inout [T], from source: IndexSet, to destination: Int) {
        // `onMove` never hands us offsets outside the list, but this is also called with
        // an issuer that may match nothing — an out-of-range offset must be a no-op,
        // not a crash on the way to rewriting stored accounts.
        let offsets = source.filter { items.indices.contains($0) }
        guard !offsets.isEmpty, (0...items.count).contains(destination) else { return }

        let moving = offsets.map { items[$0] }
        for index in offsets.sorted(by: >) {
            items.remove(at: index)
        }
        items.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
    }
}
