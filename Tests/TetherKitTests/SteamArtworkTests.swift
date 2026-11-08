import Foundation
import Testing
@testable import TetherKit

@Suite struct SteamArtworkTests {
    let home = TempHome()

    private func artwork(_ download: @escaping RuntimeDownloader) -> SteamArtwork {
        SteamArtwork(paths: home.paths, download: download)
    }

    private func tempFile(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("art-\(UUID().uuidString)")
        try Data(bytes).write(to: url)
        return url
    }

    private let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 1, count: 64)

    @Test func urlIsHTTPSOnTheValveCDNAndNeedsAPositiveID() {
        #expect(SteamArtwork.url(appID: 480)?.absoluteString == "https://cdn.cloudflare.steamstatic.com/steam/apps/480/header.jpg")
        #expect(SteamArtwork.url(appID: 0) == nil)
        #expect(SteamArtwork.url(appID: -5) == nil)
    }

    @Test func downloadsOnceThenServesFromCache() async throws {
        let calls = Counter()
        let bytes = jpeg
        let art = artwork { _ in calls.increment(); return try self.tempFile(bytes) }
        let first = await art.fetch(appID: 480)
        let second = await art.fetch(appID: 480)
        #expect(first != nil && first == second)
        #expect(calls.value == 1)
        #expect(art.cachedFile(appID: 480) == first)
        #expect(try Data(contentsOf: first!) == Data(bytes))
    }

    @Test func rejectsNonImagesAndRemembersTheAnswer() async throws {
        let calls = Counter()
        let art = artwork { _ in calls.increment(); return try self.tempFile(Array("<html>not an image at all</html>".utf8)) }
        #expect(await art.fetch(appID: 7) == nil)
        #expect(await art.fetch(appID: 7) == nil)
        #expect(calls.value == 1, "a rejected response must not be requested again right away")
        #expect(art.cachedFile(appID: 7) == nil)
    }

    @Test func rejectsOversizedFiles() async throws {
        let big = [0xFF, 0xD8, 0xFF] as [UInt8] + Array(repeating: 0, count: SteamArtwork.maxBytes + 1)
        let art = artwork { _ in try self.tempFile(big) }
        #expect(await art.fetch(appID: 9) == nil)
        #expect(art.cachedFile(appID: 9) == nil)
    }

    @Test func aMissingImageIsNotRetriedButOfflineIs() async {
        let missing = Counter(), offline = Counter()
        let a = artwork { _ in missing.increment(); throw URLError(.badServerResponse) }
        #expect(await a.fetch(appID: 1) == nil)
        #expect(await a.fetch(appID: 1) == nil)
        #expect(missing.value == 1)

        let b = artwork { _ in offline.increment(); throw URLError(.notConnectedToInternet) }
        #expect(await b.fetch(appID: 2) == nil)
        #expect(await b.fetch(appID: 2) == nil)
        #expect(offline.value == 2, "being offline must not be remembered as 'no art'")
    }

    @Test func invalidIDNeverReachesTheNetwork() async {
        let art = artwork { _ in Issue.record("must not download"); throw URLError(.badURL) }
        #expect(await art.fetch(appID: 0) == nil)
    }
}
