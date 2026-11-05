import AppKit
import SwiftUI

/// Renders this app's own SwiftUI views to a PNG for layout review, without credentials or API calls.
enum PreviewRenderer {
    @MainActor static func render(to url: URL, showImport: Bool, local: Bool, editor: Bool) {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let store = TranscribeStore(preview: true)
        if local { store.modeRaw = "local" }
        if showImport { store.newTranscription() }
        let content: AnyView
        if editor, let segment = store.document?.segments.first { content = AnyView(SegmentEditor(segment: segment)) }
        else { content = AnyView(ContentView()) }
        let hosting = NSHostingView(rootView: content.environmentObject(store).tint(Palette.accent).preferredColorScheme(.light))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: editor ? 772 : 1320, height: editor ? 512 : 900), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = hosting; window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            hosting.layoutSubtreeIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { print("Anteprima non disponibile"); exit(1) }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            do {
                guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
                try data.write(to: url); print("Anteprima salvata: \(url.path)"); exit(0)
            } catch { print(error.localizedDescription); exit(1) }
        }
        withExtendedLifetime(window) { application.run() }
    }
}
