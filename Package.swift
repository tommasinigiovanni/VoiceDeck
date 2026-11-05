// swift-tools-version: 6.2
import PackageDescription
import Foundation

// Optional local source snapshot for environments that allow HTTPS downloads but restrict Git DNS.
let fluidAudio: Package.Dependency = ProcessInfo.processInfo.environment["VOICEDECK_FLUIDAUDIO_PATH"].map {
    .package(name: "FluidAudio", path: $0, traits: [])
} ?? .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: [])

let package = Package(
    name: "VoiceDeck",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "VoiceDeck", targets: ["VoiceDeck"]),
               .executable(name: "TranscribeCheck", targets: ["TranscribeCheck"])],
    dependencies: [fluidAudio],
    targets: [
        .target(name: "TranscribeCore", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .executableTarget(name: "VoiceDeck", dependencies: ["TranscribeCore"], resources: [.process("Resources")]),
        .executableTarget(name: "TranscribeCheck", dependencies: ["TranscribeCore"]),
        .testTarget(name: "TranscribeCoreTests", dependencies: ["TranscribeCore"])
    ],
    swiftLanguageModes: [.v5]
)
