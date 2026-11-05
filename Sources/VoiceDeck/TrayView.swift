import SwiftUI
import TranscribeCore

struct TrayView: View {
    @EnvironmentObject private var store: TranscribeStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(nsImage: NSImage(contentsOf: Bundle.module.url(forResource: "AppIcon", withExtension: "png")!)!)
                    .resizable().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text("VoiceDeck").font(.system(size: 15, weight: .semibold))
                    Text(store.displayedMode.title).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if store.isBusy {
                VStack(alignment: .leading, spacing: 9) {
                    Text(store.phase).font(.system(size: 12)).lineLimit(3)
                    ProgressView(value: store.progress)
                    HStack {
                        Text("\(Int(store.progress * 100))%").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Interrompi") { store.cancel() }.controlSize(.small)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.document?.title ?? store.sourceURL?.lastPathComponent ?? "Pronto per il tuo audio")
                        .font(.system(size: 12, weight: .medium)).lineLimit(2)
                    Text(store.phase).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            if let error = store.error {
                Text(error).font(.system(size: 10)).foregroundStyle(.red).lineLimit(4)
            }
            Button { showWindow() } label: {
                Label("Apri VoiceDeck", systemImage: "macwindow").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.borderedProminent)
            Button {
                showWindow(); store.newTranscription(); store.chooseFile()
            } label: { Label("Importa audio…", systemImage: "waveform.badge.plus").frame(maxWidth: .infinity, alignment: .leading) }
                .disabled(store.isBusy)
            if !store.isBusy, store.sourceURL != nil, store.document?.isComplete != true {
                Button(store.document == nil ? "Trascrivi audio" : "Riprendi trascrizione") { showWindow(); store.start() }
            }
            if store.player != nil {
                HStack {
                    Button { store.togglePlayback() } label: { Image(systemName: store.playing ? "pause.fill" : "play.fill") }.buttonStyle(.plain)
                    Text(Timecode.display(store.playhead)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            Divider()
            HStack {
                Button("Impostazioni…") { NSApp.activate(ignoringOtherApps: true); openSettings() }.buttonStyle(.plain)
                Spacer()
                Button("Esci") { NSApp.terminate(nil) }.buttonStyle(.plain)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(18).frame(width: 310)
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
