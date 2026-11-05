import Foundation
import CoreML

public struct ResourceSnapshot: Sendable {
    public let hasNeuralEngine: Bool
    public let lowPower: Bool
    public let thermalLevel: Int
    public let memoryPressure: Int
    public init(hasNeuralEngine: Bool, lowPower: Bool, thermalLevel: Int, memoryPressure: Int) {
        self.hasNeuralEngine = hasNeuralEngine; self.lowPower = lowPower
        self.thermalLevel = thermalLevel; self.memoryPressure = memoryPressure
    }
    public static var current: Self {
        let info = ProcessInfo.processInfo
        return Self(hasNeuralEngine: neuralEngineAvailable, lowPower: info.isLowPowerModeEnabled,
                    thermalLevel: info.thermalState.rawValue, memoryPressure: MemoryPressure.shared.level)
    }
    private static let neuralEngineAvailable = MLComputeDevice.allComputeDevices.contains {
        if case .neuralEngine = $0 { return true }; return false
    }
}

public struct ExecutionPlan: Sendable {
    public let usesGPU: Bool
    public let hasNeuralEngine: Bool
    public var encoderUnits: MLComputeUnits { usesGPU ? .cpuAndGPU : hasNeuralEngine ? .cpuAndNeuralEngine : .cpuOnly }
    public var otherUnits: MLComputeUnits { hasNeuralEngine ? .cpuAndNeuralEngine : .cpuOnly }
    public var description: String {
        usesGPU ? "Encoder su CPU/GPU · decoder su \(hasNeuralEngine ? "CPU/Neural Engine" : "CPU")" : hasNeuralEngine ? "CPU e Neural Engine · efficienza" : "CPU · compatibilità"
    }
    public static func choose(preferGPU: Bool, resources: ResourceSnapshot) -> Self {
        Self(usesGPU: preferGPU && !resources.lowPower && resources.thermalLevel < 2 && resources.memoryPressure == 0,
             hasNeuralEngine: resources.hasNeuralEngine)
    }
}

public enum ResourceGovernor {
    /// Check between inference calls, preserving completed transcript parts on memory pressure.
    public static func checkpoint(progress: @Sendable (String) async -> Void = { _ in }) async throws {
        try Task.checkCancellation()
        while true {
            let resources = ResourceSnapshot.current
            if resources.memoryPressure >= 2 {
                throw TranscribeError.message("macOS segnala pressione critica sulla memoria. Le parti completate sono salvate: libera memoria e premi Riprendi.")
            }
            guard resources.thermalLevel >= 3 else { return }
            await progress("Pausa per temperatura elevata del Mac. Ripresa automatica appena possibile…")
            try await Task.sleep(for: .seconds(1))
        }
    }
}

private final class MemoryPressure: @unchecked Sendable {
    static let shared = MemoryPressure()
    private let lock = NSLock()
    private var value = 0
    private let source: DispatchSourceMemoryPressure
    var level: Int { lock.lock(); defer { lock.unlock() }; return value }
    private init() {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.source.data
            self.lock.lock()
            self.value = flags.contains(.critical) ? 2 : flags.contains(.warning) ? 1 : 0
            self.lock.unlock()
        }
        source.resume()
    }
}
