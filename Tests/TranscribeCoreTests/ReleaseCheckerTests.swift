import XCTest
@testable import TranscribeCore

private final class ReleaseProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class ReleaseCheckerTests: XCTestCase {
    override func tearDown() { ReleaseProtocol.handler = nil; super.tearDown() }
    private func checker() -> ReleaseChecker {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ReleaseProtocol.self]
        return ReleaseChecker(session: URLSession(configuration: config))
    }
    private func payload(version: String = "v0.3.0", page: String = "https://github.com/tommasinigiovanni/VoiceDeck/releases/tag/v0.3.0",
                         download: String = "https://github.com/tommasinigiovanni/VoiceDeck/releases/download/v0.3.0/VoiceDeck-macOS.zip",
                         prerelease: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tag_name": version, "html_url": page, "draft": false, "prerelease": prerelease,
            "assets": [["name": "VoiceDeck-macOS.zip", "state": "uploaded", "browser_download_url": download]]])
    }
    func testVersionsUseNumericOrderingAndNormalizeComponents() throws {
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("v0.10.0")), try XCTUnwrap(AppVersion("0.9.9")))
        XCTAssertEqual(AppVersion("1.2"), AppVersion("1.2.0"))
        XCTAssertNil(AppVersion("development")); XCTAssertNil(AppVersion("1.2.3-beta"))
        XCTAssertNil(AppVersion("1..2")); XCTAssertNil(AppVersion("-1.2.3"))
    }
    func testNewReleaseIncludesDownloadAndUsesPublicEndpointWithoutCredentials() async throws {
        let data = try payload()
        ReleaseProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/tommasinigiovanni/VoiceDeck/releases/latest")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "VoiceDeck/0.2.1")
            return (200, data)
        }
        let release = try await checker().check(currentVersion: "0.2.1")
        XCTAssertEqual(release?.version, "v0.3.0")
        XCTAssertEqual(release?.downloadURL?.lastPathComponent, "VoiceDeck-macOS.zip")
    }
    func testSameOrOlderReleaseNeverSuggestsDowngrade() async throws {
        let data = try payload()
        ReleaseProtocol.handler = { _ in (200, data) }
        let same = try await checker().check(currentVersion: "0.3.0")
        let newer = try await checker().check(currentVersion: "0.4.0")
        XCTAssertNil(same); XCTAssertNil(newer)
    }
    func testUntrustedDownloadIsNotOfferedButReleasePageRemainsAvailable() async throws {
        let data = try payload(download: "https://example.com/VoiceDeck.zip")
        ReleaseProtocol.handler = { _ in (200, data) }
        let release = try await checker().check(currentVersion: "0.2.1")
        XCTAssertNil(release?.downloadURL); XCTAssertNotNil(release?.releaseURL)
    }
    func testInvalidReleasePageAndPrereleaseAreRejected() async throws {
        for data in [try payload(page: "https://github.com/other/VoiceDeck/releases/tag/v0.3.0"), try payload(prerelease: true)] {
            ReleaseProtocol.handler = { _ in (200, data) }
            do { _ = try await checker().check(currentVersion: "0.2.1"); XCTFail("Expected invalid release error") }
            catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
    }
    func testRateLimitAndOfflineAreNotReportedAsUpToDate() async throws {
        ReleaseProtocol.handler = { _ in (403, Data()) }
        do { _ = try await checker().check(currentVersion: "0.2.1"); XCTFail("Expected rate limit error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("limitato")) }
        ReleaseProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await checker().check(currentVersion: "0.2.1"); XCTFail("Expected network error") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
    }
}
