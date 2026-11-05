import SwiftUI
import TranscribeCore

struct SegmentEditor: View {
    @EnvironmentObject private var store: TranscribeStore
    @Environment(\.dismiss) private var dismiss
    let segment: TranscriptSegment
    @State private var text: String
    @State private var speaker: String

    init(segment: TranscriptSegment) {
        self.segment = segment
        _text = State(initialValue: segment.text)
        _speaker = State(initialValue: segment.speakerID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Correggi il passaggio").font(.title2.weight(.semibold))
                    Text(segment.start.map { "\(Timecode.display($0)) · Parte \(segment.chunkIndex + 1)" } ?? "Timestamp non disponibile")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.playSegment(segment) } label: { Label("Riascolta", systemImage: "play.fill") }
                    .disabled(store.player == nil || segment.start == nil)
            }
            Picker("Speaker", selection: $speaker) {
                Text("Non attribuito").tag("")
                ForEach(store.document?.speakerIDs ?? [], id: \.self) { id in Text(store.document?.speakerName(id) ?? id).tag(id) }
            }.frame(maxWidth: 310)
            TextEditor(text: $text).font(.system(size: 15)).lineSpacing(6).padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10)) }
            HStack {
                Text("Le correzioni vengono salvate nell’archivio e incluse negli export.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Salva") {
                    if store.editSegment(segment.id, text: text, speakerID: speaker.isEmpty ? nil : speaker) { dismiss() }
                }.buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 720, height: 460).background(Color(nsColor: .windowBackgroundColor))
    }
}
