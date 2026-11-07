import SwiftUI
import AppKit
import TranscribeCore

@main
enum TranscribeLauncher {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--preview"), args.indices.contains(index + 1), !args[index + 1].hasPrefix("--") {
            PreviewRenderer.render(to: URL(fileURLWithPath: args[index + 1]), showImport: args.contains("--import-preview"),
                                   local: args.contains("--local-preview"), editor: args.contains("--editor-preview"))
        } else { VoiceDeckApp.main() }
    }
}

struct VoiceDeckApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = TranscribeStore(preview: CommandLine.arguments.contains("--preview"))
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        Window("VoiceDeck", id: "main") {
            ContentView().environmentObject(store).environmentObject(updater)
                .frame(minWidth: 1060, minHeight: 720)
                .tint(Palette.accent)
                .alert("VoiceDeck", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
                .onAppear { store.configureShortcut() }
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nuova trascrizione") { store.newTranscription() }.keyboardShortcut("n").disabled(store.blocksChanges)
                Button("Importa audio…") { store.chooseFile() }.keyboardShortcut("o").disabled(store.blocksChanges)
            }
            CommandGroup(after: .appInfo) {
                Button("Controlla aggiornamenti…") {
                    openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true); updater.check()
                }.disabled(updater.checking)
            }
            CommandMenu("Registrazione") {
                Button(store.isRecording ? "Ferma e trascrivi" : "Registra dal microfono") { store.toggleRecording() }.disabled(!store.canToggleRecording)
                Button("Annulla registrazione") { store.discardRecording() }.disabled(!store.isRecording)
            }
        }
        Settings { SettingsView().environmentObject(store).tint(Palette.accent) }
        MenuBarExtra("VoiceDeck", systemImage: store.isRecording ? "record.circle.fill" : "waveform") {
            TrayView().environmentObject(store).tint(Palette.accent)
        }.menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Read the artwork from this build rather than a cached LaunchServices icon.
        let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "png")
        if let iconURL, let icon = NSImage(contentsOf: iconURL) { NSApp.applicationIconImage = icon }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
