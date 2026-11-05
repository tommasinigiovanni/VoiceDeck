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
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = TranscribeStore(preview: CommandLine.arguments.contains("--preview"))

    var body: some Scene {
        Window("VoiceDeck", id: "main") {
            ContentView().environmentObject(store)
                .frame(minWidth: 1060, minHeight: 720)
                .tint(Palette.accent)
                .alert("VoiceDeck", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nuova trascrizione") { store.newTranscription() }.keyboardShortcut("n").disabled(store.isBusy)
                Button("Importa audio…") { store.chooseFile() }.keyboardShortcut("o").disabled(store.isBusy)
            }
        }
        Settings { SettingsView().environmentObject(store).tint(Palette.accent) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Palette {
    static let accent = Color(red: 0.38, green: 0.70, blue: 0.28)
    static let ink = Color(red: 0.12, green: 0.15, blue: 0.13)
    static let speakerColors: [Color] = [.teal, .indigo, .orange, .pink, .blue, .purple, .brown, .green]
    static func speaker(_ id: String?, in ids: [String]) -> Color {
        guard let id, let index = ids.firstIndex(of: id) else { return .secondary }
        return speakerColors[index % speakerColors.count]
    }
}
