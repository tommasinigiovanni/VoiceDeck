import XCTest
@testable import TranscribeCore

private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class OpenRouterClientTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }
    override func tearDown() { StubProtocol.handler = nil; super.tearDown() }

    func testRequestUsesDedicatedEndpointAndVerboseWordTimestamps() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let wav = WAV.encode(pcm: Data(count: 320))
        try wav.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        StubProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/audio/transcriptions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            var streamData = Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    guard count > 0 else { break }; streamData.append(contentsOf: bytes.prefix(count))
                }
            }
            let body = request.httpBody ?? streamData
            XCTAssertFalse(body.isEmpty)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "nvidia/nemotron-3.5-transcribe")
            XCTAssertEqual(json["response_format"] as? String, "verbose_json")
            XCTAssertEqual(json["timestamp_granularities"] as? [String], ["segment", "word"])
            XCTAssertEqual(json["language"] as? String, "it")
            let input = try XCTUnwrap(json["input_audio"] as? [String: String])
            XCTAssertEqual(Data(base64Encoded: input["data"]!), wav)
            return (200, Data(#"{"text":"Ciao","words":[{"word":"Ciao","start":0,"end":0.01}]}"#.utf8))
        }
        let chunk = AudioChunk(index: 0, url: url, offset: 0, duration: 0.01, byteCount: wav.count)
        let result = try await OpenRouterClient(apiKey: "test-key", session: session()).transcribe(chunk: chunk, language: "it")
        XCTAssertEqual(result.segments.first?.text, "Ciao")
    }

    func testUnauthorizedErrorIsActionable() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try WAV.encode(pcm: Data(count: 320)).write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        StubProtocol.handler = { _ in (401, Data(#"{"error":{"message":"Invalid API key"}}"#.utf8)) }
        let chunk = AudioChunk(index: 0, url: url, offset: 0, duration: 0.01, byteCount: 364)
        do { _ = try await OpenRouterClient(apiKey: "test", session: session()).transcribe(chunk: chunk); XCTFail("Expected error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Chiave API")) }
    }

    func testCapabilitiesReadActualDiarizationFlags() async throws {
        StubProtocol.handler = { _ in (200, Data(#"{"data":{"endpoints":[{"provider_name":"PrimeIntellect","tag":"primeintellect/bf16","supports_diarization":false}]}}"#.utf8)) }
        let providers = try await OpenRouterClient(apiKey: "", session: session()).capabilities()
        XCTAssertEqual(providers.count, 1)
        XCTAssertFalse(providers[0].supportsDiarization)
    }
}
