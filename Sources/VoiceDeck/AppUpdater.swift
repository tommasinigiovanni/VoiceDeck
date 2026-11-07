import SwiftUI
import TranscribeCore

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var checking = false
    @Published private(set) var release: AppRelease?
    @Published private(set) var message = ""
    @Published private(set) var failed = false
    @Published var showsResult = false
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development" }

    func check() {
        guard !checking else { return }
        checking = true; failed = false; release = nil; showsResult = false
        Task {
            defer { checking = false; showsResult = true }
            do {
                release = try await ReleaseChecker().check(currentVersion: Self.currentVersion)
                message = release.map { "È disponibile VoiceDeck \($0.version)." } ?? "VoiceDeck è aggiornato. Nessuna versione più recente disponibile."
            } catch { failed = true; message = error.localizedDescription }
        }
    }
}

struct AppFooter: View {
    @EnvironmentObject private var store: TranscribeStore
    @EnvironmentObject private var updater: AppUpdater
    var body: some View {
        HStack(spacing: 14) {
            Label(store.isRecording ? "Microfono attivo" : "Registrazione rapida: \(store.shortcutTitle)",
                  systemImage: store.isRecording ? "record.circle.fill" : "keyboard")
                .foregroundStyle(store.isRecording ? .red : .secondary)
            Spacer(minLength: 12)
            Text("VoiceDeck \(AppUpdater.currentVersion)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            if updater.checking { ProgressView().controlSize(.mini) }
            Button { updater.check() } label: {
                Label(updater.checking ? "Verifica in corso…" : "Controlla aggiornamenti", systemImage: "arrow.triangle.2.circlepath")
            }.buttonStyle(.plain).foregroundStyle(Palette.accent).disabled(updater.checking)
                .popover(isPresented: $updater.showsResult, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(updater.failed ? "Verifica non riuscita" : updater.release == nil ? "App aggiornata" : "Aggiornamento disponibile",
                              systemImage: updater.failed ? "exclamationmark.triangle" : updater.release == nil ? "checkmark.circle" : "arrow.down.circle")
                            .font(.headline)
                        Text(updater.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text("Versione installata: \(AppUpdater.currentVersion)").font(.caption).foregroundStyle(.secondary)
                        if let release = updater.release {
                            if let download = release.downloadURL { Link("Scarica \(release.version)", destination: download).buttonStyle(.borderedProminent) }
                            Link("Note di rilascio", destination: release.releaseURL)
                            Text("Scarica lo ZIP, chiudi VoiceDeck e sostituisci l’app. Le trascrizioni rimangono nell’archivio del Mac.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if updater.failed {
                            Link("Apri le release su GitHub", destination: ReleaseChecker.repositoryURL.appendingPathComponent("releases"))
                        }
                    }.padding(20).frame(width: 330)
                }
        }.font(.system(size: 10)).padding(.horizontal, 24).padding(.vertical, 12)
            .background(Palette.background)
            .overlay(alignment: .top) { Divider() }
    }
}
