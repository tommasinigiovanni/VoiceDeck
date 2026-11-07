import SwiftUI
import UniformTypeIdentifiers
import TranscribeCore

struct ContentView: View {
    @EnvironmentObject private var store: TranscribeStore
    @Environment(\.openSettings) private var openSettings
    @State private var dropTarget = false
    @State private var showSpeakers = false
    @State private var editingSegment: TranscriptSegment?
    @State private var showVocabulary = false
    @State private var vocabularyReview: VocabularyReviewDraft?

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 246)
            Rectangle().fill(Palette.subtle.opacity(0.07)).frame(width: 1)
            VStack(spacing: 0) {
                workspaceBar
                VStack(spacing: 0) {
                    if store.isCapturing { recordingBar }
                    if store.showsCredits { CreditsView() }
                    else if let document = store.document {
                        transcript(document).voiceDeckCard().clipShape(RoundedRectangle(cornerRadius: 18)).padding(24)
                    } else { importView }
                    if !store.showsCredits, store.sourceURL != nil || store.document != nil { statusBar.fixedSize(horizontal: false, vertical: true) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                AppFooter().fixedSize(horizontal: false, vertical: true)
            }
        }.background(Palette.background).foregroundStyle(Palette.ink)
        .sheet(isPresented: $showSpeakers) { SpeakersView().environmentObject(store) }
        .sheet(isPresented: $showVocabulary) { VocabularyView().environmentObject(store) }
        .sheet(item: $vocabularyReview) { draft in VocabularyReview(documentID: draft.id, suggestions: draft.suggestions).environmentObject(store) }
        .sheet(item: $editingSegment) { segment in SegmentEditor(segment: segment).environmentObject(store) }
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
            guard !store.blocksChanges, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }; Task { @MainActor in store.importFile(url) }
            }
            return true
        }
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 12).stroke(Palette.accent, lineWidth: 3).padding(8).allowsHitTesting(false) } }
    }

    // Keep workspace actions inside the content area. The native title bar owns
    // the window title and its controls, without a split-view toolbar overlay.
    private var workspaceBar: some View {
        HStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                Label(store.showsCredits ? "Crediti" : store.document == nil ? "Nuova trascrizione" : "Trascrizione", systemImage: store.showsCredits ? "info.circle" : "text.bubble")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Image(systemName: "text.bubble").foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            if store.showsCredits {
                Button { store.showsCredits = false } label: { Label("Torna alla trascrizione", systemImage: "arrow.left") }
            } else {
                if store.document != nil {
                    Menu {
                        Button("Rivedi suggerimenti del dizionario…") {
                            if let id = store.document?.id { vocabularyReview = VocabularyReviewDraft(id: id, suggestions: store.vocabularySuggestions()) }
                        }.disabled(store.vocabulary.isEmpty)
                        Button("Gestisci dizionario personale…") { showVocabulary = true }
                    } label: { Label("Correzioni", systemImage: "text.badge.checkmark") }.fixedSize().disabled(store.blocksChanges)
                    Button { showSpeakers = true } label: { Label("Speaker", systemImage: "person.2") }.disabled(store.blocksChanges)
                    Button { store.copyTranscript() } label: { Label("Copia", systemImage: "doc.on.doc") }.disabled(store.document?.segments.isEmpty ?? true)
                    Menu {
                        Button("Testo (.txt)") { store.export("txt") }
                        Button("Markdown (.md)") { store.export("md") }
                        Button("JSON (.json)") { store.export("json") }
                        Button("Sottotitoli (.srt)") { store.export("srt") }
                            .disabled(store.document?.segments.contains(where: { $0.start != nil && $0.end != nil }) != true)
                    } label: { Label("Esporta", systemImage: "square.and.arrow.up") }.fixedSize()
                    .disabled(store.document?.segments.isEmpty ?? true)
                }
                Button { store.toggleRecording() } label: {
                    Label(store.isRecording ? "Ferma e trascrivi" : "Registra", systemImage: store.isRecording ? "stop.circle.fill" : "mic")
                }.buttonStyle(.borderedProminent).disabled(!store.canToggleRecording)
                    .help("Registrazione rapida · \(store.shortcutTitle)")
            }
        }
        .labelStyle(.titleAndIcon).font(.system(size: 11)).buttonStyle(.bordered).controlSize(.small)
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Palette.background).overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private var recordingBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "record.circle.fill").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.isRecording ? "Registrazione dal microfono" : "Accesso al microfono…").font(.callout.weight(.semibold))
                Text(store.mode.title).font(.caption).foregroundStyle(.secondary)
            }
            Text(Timecode.display(store.recorder.elapsed)).monospacedDigit()
            ProgressView(value: store.recorder.level).frame(width: 90).tint(.red)
            Spacer()
            Button("Annulla") { store.discardRecording() }.disabled(!store.isRecording)
            Button("Ferma e trascrivi") { store.toggleRecording() }.buttonStyle(.borderedProminent).disabled(!store.isRecording)
        }.padding(18).background(Color.red.opacity(0.06))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSImage(contentsOf: Bundle.module.url(forResource: "AppIcon", withExtension: "png")!)!)
                    .resizable().interpolation(.high).frame(width: 32, height: 32)
                Text("VoiceDeck").font(.system(size: 18, weight: .semibold)).tracking(-0.6)
            }.padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 8)
            Text("IL TUO SPAZIO AUDIO").font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(2).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 28)
            Button { store.newTranscription(); store.chooseFile() } label: {
                Label("Nuova trascrizione", systemImage: "plus").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).disabled(store.blocksChanges).padding(.horizontal, 20)
            Button { store.toggleRecording() } label: {
                Label(store.isRecording ? "Ferma e trascrivi" : "Registra dal microfono", systemImage: store.isRecording ? "stop.circle.fill" : "mic")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                .disabled(!store.canToggleRecording).padding(.horizontal, 20).padding(.top, 12)
            HStack { Text("LIBRERIA").font(.system(size: 10, weight: .semibold)).tracking(1.3); Spacer(); Text("\(store.documents.count)").monospacedDigit() }
                .foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 10)
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(store.documents) { doc in
                        Button { store.select(doc.id) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: doc.isComplete ? "text.bubble" : "clock.arrow.circlepath")
                                    .font(.system(size: 16)).foregroundStyle(doc.isComplete ? Palette.accent : Palette.amber).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(doc.title).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                    HStack(spacing: 4) {
                                        Text(doc.createdAt, format: .dateTime.day().month(.abbreviated).year(.twoDigits))
                                        Text("·"); Text(Timecode.display(doc.duration))
                                    }.lineLimit(1)
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(store.selectedID == doc.id && !store.showsCredits ? Palette.accent : Palette.ink)
                                .background(store.selectedID == doc.id && !store.showsCredits ? Palette.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).disabled(store.blocksChanges)
                    }
                }.padding(.horizontal, 16)
                if store.documents.isEmpty {
                    Text("Le tue trascrizioni appariranno qui.").font(.system(size: 12)).foregroundStyle(.tertiary).padding(22)
                }
            }
            MacStatusCard().padding(.horizontal, 20).padding(.top, 12)
            Button { openSettings() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3").frame(width: 16)
                    Text("Impostazioni")
                    Spacer()
                    Text("⌘,").font(.system(size: 10, design: .monospaced))
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(12).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 8)
            Button { store.showsCredits = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle").frame(width: 16)
                    Text("Crediti")
                    Spacer()
                }.font(.system(size: 11, weight: store.showsCredits ? .semibold : .regular))
                    .foregroundStyle(store.showsCredits ? Palette.accent : Color.secondary)
                    .padding(12).contentShape(Rectangle())
                    .background(store.showsCredits ? Palette.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(Palette.sidebar)
    }

    private var importView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text("DA AUDIO A CONVERSAZIONE").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.8).foregroundStyle(.secondary); Spacer()
                    StatusBadge(text: store.mode == .local ? "Sul tuo Mac" : "OpenRouter") }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ogni voce, parola per parola.").font(.system(size: 32, weight: .semibold)).tracking(-1)
                    Text("Importa una registrazione. Ottieni una trascrizione consultabile, con timestamp e speaker distinti.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).frame(maxWidth: 560, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Picker("Modalità di trascrizione", selection: $store.modeRaw) {
                        ForEach(TranscriptionMode.allCases, id: \.rawValue) { mode in Text(mode.title).tag(mode.rawValue) }
                    }.pickerStyle(.segmented).labelsHidden().disabled(store.blocksChanges)
                    Text(store.mode == .local ? "Audio e testo rimangono sul Mac. Nessuna chiave API; circa 480 MB per Parakeet al primo utilizzo." : "Il testo viene generato da Nemotron 3.5 su OpenRouter, con la tua chiave API.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(16).voiceDeckCard(radius: 14)
                Button { store.chooseFile() } label: {
                    VStack(spacing: 16) {
                        Image(systemName: store.sourceURL == nil ? "waveform.badge.plus" : "waveform.circle.fill")
                            .font(.system(size: 40, weight: .light)).foregroundStyle(Palette.accent)
                        if let url = store.sourceURL {
                            Text(url.lastPathComponent).font(.system(size: 17, weight: .medium)).lineLimit(2)
                            Text("\(Timecode.display(store.sourceDuration))  ·  \(ByteCountFormatter.string(fromByteCount: store.sourceSize, countStyle: .file))")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            Text("Fai clic per cambiare file").font(.system(size: 11)).foregroundStyle(.tertiary)
                        } else {
                            Text("Trascina qui il tuo audio").font(.system(size: 18, weight: .medium))
                            Text("oppure fai clic per scegliere un file").font(.system(size: 13)).foregroundStyle(.secondary)
                            Text("MP3, M4A, WAV, AIFF, FLAC e formati leggibili da macOS")
                                .font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 32)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.accent.opacity(0.40), style: StrokeStyle(lineWidth: 1, dash: [6, 5])) }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(store.blocksChanges)
                HStack(alignment: .top, spacing: 12) {
                    feature("scissors", "File grandi, già gestiti", store.mode == .local ? "Lettura a blocchi per registrazioni lunghe." : "Suddivisione automatica sotto i 25 MB per richiesta.")
                    feature("person.2.wave.2", "Speaker sul Mac", "Nemotron 3 Diarization segue le voci nell’intero audio.")
                    feature("square.and.arrow.up", "Pronto da esportare", "Testo, Markdown, JSON e sottotitoli SRT.")
                }
                HStack {
                    Label(store.mode == .local || store.localSpeakers ? "Speaker locali attivi" : "Solo speaker del provider", systemImage: "desktopcomputer")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button { openSettings() } label: { Text("Impostazioni") }.buttonStyle(.bordered)
                    Button { store.start() } label: { Label("Trascrivi audio", systemImage: "arrow.right").padding(.horizontal, 12).padding(.vertical, 5) }
                        .buttonStyle(.borderedProminent).disabled(store.sourceURL == nil || store.blocksChanges)
                }
                Text("L’analisi delle voci avviene sul Mac con Nemotron 3 Diarization: circa 190 MB al primo utilizzo, condivisi tra le due modalità.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(3)
            }.padding(24).frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
        }
    }

    private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Palette.accent)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading).voiceDeckCard(radius: 14)
    }

    private func transcript(_ doc: TranscriptDocument) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(doc.isComplete ? "TRASCRIZIONE" : "IN LAVORAZIONE").font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(.secondary)
                        Text(doc.title).font(.system(size: 27, weight: .semibold)).lineLimit(2)
                        HStack(spacing: 14) {
                            Label(Timecode.display(doc.duration), systemImage: "clock")
                            Label("\(doc.speakerIDs.count) speaker", systemImage: "person.2")
                            Label("\(doc.completedChunks)/\(doc.totalChunks) parti", systemImage: "square.stack")
                            Label(doc.model == TranscriptionMode.localModelID ? "Locale" : "OpenRouter", systemImage: doc.model == TranscriptionMode.localModelID ? "desktopcomputer" : "network")
                            if doc.cost > 0 { Text(String(format: "$%.4f", doc.cost)) }
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if doc.isComplete { StatusBadge(text: "Completata") }
                }
                HStack(spacing: 12) {
                    HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Cerca nella trascrizione", text: $store.search).textFieldStyle(.plain)
                        if !store.search.isEmpty { Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                    }.padding(9).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    Picker("Speaker", selection: $store.selectedSpeaker) {
                        Text("Tutti gli speaker").tag("")
                        ForEach(doc.speakerIDs, id: \.self) { id in Text(doc.speakerName(id)).tag(id) }
                    }.labelsHidden().frame(width: 175)
                }
                if let warning = doc.warnings.first {
                    Label(warning, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                        .help(doc.warnings.joined(separator: "\n"))
                }
            }.padding(24)
            Divider()
            if doc.segments.isEmpty {
                VStack(spacing: 16) { Image(systemName: "waveform").font(.system(size: 38)).foregroundStyle(Palette.accent)
                    Text(store.isBusy ? "La tua trascrizione sta prendendo forma." : "La trascrizione è pronta da riprendere.").font(.system(size: 16, weight: .medium))
                    Text("Le parti completate appariranno qui e verranno salvate automaticamente.").foregroundStyle(.secondary).font(.system(size: 12))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.visibleSegments) { segment in segmentRow(segment, doc: doc) }
                        if store.visibleSegments.isEmpty { Text("Nessun passaggio trovato.").foregroundStyle(.secondary).padding(32) }
                    }.padding(.horizontal, 32).padding(.vertical, 8)
                }.textSelection(.enabled)
            }
        }
    }

    private func segmentRow(_ segment: TranscriptSegment, doc: TranscriptDocument) -> some View {
        let color = Palette.speaker(segment.speakerID, in: doc.speakerIDs)
        return HStack(alignment: .top, spacing: 18) {
            Button { store.playSegment(segment) } label: {
                Text(segment.start.map(Timecode.display) ?? "—").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }.buttonStyle(.plain).disabled(segment.start == nil || store.player == nil).frame(width: 68, alignment: .leading).padding(.top, 3)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(doc.speakerName(segment.speakerID)).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
                    Text("· Parte \(segment.chunkIndex + 1)").font(.system(size: 10)).foregroundStyle(.tertiary)
                    if segment.editedAt != nil { Text("· Modificato").font(.system(size: 10)).foregroundStyle(.tertiary) }
                    Spacer()
                    Button { editingSegment = segment } label: { Image(systemName: "pencil").font(.system(size: 12)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Modifica questo passaggio").disabled(store.isBusy)
                }
                Text(segment.text).font(.system(size: 15)).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle()).onTapGesture { store.playSegment(segment) }
                    .help("Fai clic per riascoltare questo punto. Usa la matita per correggere il testo.")
            }
        }.padding(.vertical, 23)
            .background(store.playing && store.playhead >= (segment.start ?? .infinity) && store.playhead < (segment.end ?? -.infinity) ? color.opacity(0.045) : .clear)
            .overlay(alignment: .bottom) { Divider().opacity(0.5) }
            .contextMenu {
                Button("Riascolta da qui") { store.playSegment(segment) }.disabled(store.player == nil || segment.start == nil)
                Button("Modifica passaggio…") { editingSegment = segment }.disabled(store.isBusy)
            }
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            if store.isBusy {
                HStack(spacing: 14) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(store.phase).font(.system(size: 11)); Spacer(); Text("\(Int(store.progress * 100))%").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
                        ProgressView(value: store.progress).tint(Palette.accent)
                    }
                    Button("Interrompi") { store.cancel() }.controlSize(.small)
                }.padding(.horizontal, 26).padding(.vertical, 15)
            } else {
                HStack(spacing: 12) {
                    Button { store.togglePlayback() } label: { Image(systemName: store.playing ? "pause.fill" : "play.fill").frame(width: 20) }
                        .buttonStyle(.plain).disabled(store.player == nil)
                    Text(Timecode.display(store.playhead)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { min(store.playhead, max(store.sourceDuration, 1)) }, set: { store.seek($0) }), in: 0...max(store.sourceDuration, 1)).disabled(store.player == nil)
                    Text(Timecode.display(store.sourceDuration)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    if store.document?.isComplete == false { Button("Riprendi") { store.start() }.buttonStyle(.borderedProminent).controlSize(.small) }
                }.padding(.horizontal, 26).padding(.top, 15)
                HStack { Circle().fill(Palette.accent).frame(width: 5, height: 5); Text(store.phase); Spacer(); Text(store.displayedMode.modelID).font(.system(size: 9, design: .monospaced)) }
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 26).padding(.top, 11).padding(.bottom, 14)
            }
        }.background(Palette.background)
    }
}
