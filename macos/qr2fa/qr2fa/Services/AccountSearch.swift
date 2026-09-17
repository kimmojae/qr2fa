import Foundation

/// 계정 목록 검색.
///
/// 찾는 사람이 기억하는 건 서비스 이름일 수도, 계정 이름일 수도, 붙여 둔 태그일 수도 있다.
/// 셋 다 훑고, 공백으로 나눈 낱말이 **전부** 어딘가에 걸릴 때만 남긴다 — `aws prod`처럼
/// 좁혀 들어가는 입력이 그래야 동작한다.
enum AccountSearch {

    static func filter(_ accounts: [Account], query: String) -> [Account] {
        let terms = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return accounts }

        return accounts.filter { account in
            let haystack = [account.displayIssuer, account.name, account.tag]
                .joined(separator: " ")
                .lowercased()
            return terms.allSatisfy(haystack.contains)
        }
    }
}
