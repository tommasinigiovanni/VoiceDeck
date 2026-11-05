import Foundation

public struct AppVersion: Comparable, Sendable {
    private let parts: [Int]
    public init?(_ string: String) {
        let value = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let tokens = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(tokens.count), tokens.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = tokens.compactMap { Int($0) }
        guard numbers.count == tokens.count else { return nil }
        parts = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

public struct AppRelease: Sendable {
    public let version: String
    public let releaseURL: URL
    public let downloadURL: URL?
}

public struct ReleaseChecker: Sendable {
    public static let repositoryURL = URL(string: "https://github.com/tommasinigiovanni/VoiceDeck")!
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func check(currentVersion: String) async throws -> AppRelease? {
        guard let current = AppVersion(currentVersion) else {
            throw TranscribeError.message("Questa build non ha un numero di versione valido. Consulta le release su GitHub.")
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/tommasinigiovanni/VoiceDeck/releases/latest")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VoiceDeck/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranscribeError.message("Risposta aggiornamenti non valida.") }
        switch http.statusCode {
        case 200: break
        case 404: throw TranscribeError.message("Non sono ancora disponibili release pubbliche su GitHub.")
        case 403, 429: throw TranscribeError.message("GitHub ha limitato le richieste. Riprova più tardi o apri le release.")
        default: throw TranscribeError.message("Verifica aggiornamenti non riuscita (HTTP \(http.statusCode)). Riprova più tardi.")
        }
        let release = try JSONDecoder().decode(Payload.self, from: data)
        guard !release.draft, !release.prerelease, let latest = AppVersion(release.tag_name) else {
            throw TranscribeError.message("La release ricevuta non è una versione stabile valida.")
        }
        guard latest > current else { return nil }
        guard let page = URL(string: release.html_url), Self.trusted(page, prefix: "/tommasinigiovanni/VoiceDeck/releases/tag/") else {
            throw TranscribeError.message("Il collegamento della release non appartiene al progetto VoiceDeck.")
        }
        let download = release.assets.first { asset in
            asset.name == "VoiceDeck-macOS.zip" && asset.state == "uploaded" &&
            URL(string: asset.browser_download_url).map { Self.trusted($0, prefix: "/tommasinigiovanni/VoiceDeck/releases/download/") } == true
        }.flatMap { URL(string: $0.browser_download_url) }
        return AppRelease(version: release.tag_name, releaseURL: page, downloadURL: download)
    }

    private static func trusted(_ url: URL, prefix: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil &&
        url.port == nil && url.path.hasPrefix(prefix)
    }
    private struct Payload: Decodable {
        let tag_name: String
        let html_url: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let state: String
        let browser_download_url: String
    }
}
