import SwiftUI
import Darwin
import TranscribeCore

struct MacStatusCard: View {
    @EnvironmentObject private var store: TranscribeStore
    private static let machine = MacSummary()

    var body: some View {
        // Cheap system readings; no model loading or resource sampling loop in the store.
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            let resources = ResourceSnapshot.current
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "laptopcomputer").font(.system(size: 22)).foregroundStyle(.secondary)
                Text(Self.machine.chip).font(.system(size: 12, weight: .medium)).lineLimit(2)
                Text("\(Self.machine.memory) · \(Self.machine.cores) core")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                StatusBadge(text: status(resources).text, color: status(resources).color)
                    .help("Condizioni del Mac: temperatura, memoria e Risparmio energetico. Possono limitare l’elaborazione locale.")
                Divider().overlay(Palette.subtle.opacity(0.04))
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: store.displayedMode == .local ? "waveform" : "network")
                        .foregroundStyle(Palette.accent).frame(width: 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.displayedMode == .local ? "Parakeet v3" : "Nemotron 3.5")
                            .font(.system(size: 11, weight: .medium))
                        Text(store.displayedMode == .local ? "Trascrizione sul Mac" : "Trascrizione via OpenRouter")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.subtle.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func status(_ resources: ResourceSnapshot) -> (text: String, color: Color) {
        if resources.memoryPressure >= 2 { return ("Memoria critica", .red) }
        if resources.thermalLevel >= 3 { return ("Temperatura critica", .red) }
        if resources.memoryPressure > 0 { return ("Memoria sotto pressione", Palette.amber) }
        if resources.thermalLevel >= 2 { return ("Temperatura elevata", Palette.amber) }
        if resources.lowPower { return ("Risparmio energetico", Palette.amber) }
        if resources.thermalLevel > 0 { return ("Temperatura in aumento", Palette.amber) }
        return ("Normale", Palette.accent)
    }
}

private struct MacSummary {
    let chip: String
    let memory = ByteCountFormatter.string(fromByteCount: Int64(clamping: ProcessInfo.processInfo.physicalMemory), countStyle: .memory)
    let cores = ProcessInfo.processInfo.processorCount

    init() {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            chip = "Questo Mac"; return
        }
        var buffer = [CChar](repeating: 0, count: size)
        chip = sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 ? String(cString: buffer) : "Questo Mac"
    }
}
