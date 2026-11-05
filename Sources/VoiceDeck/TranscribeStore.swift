import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import TranscribeCore

@MainActor
final class TranscribeStore: ObservableObject {
    @Published var documents: [TranscriptDocument] = []
    @Published var selectedID: UUID?
    @Published var document: TranscriptDocument?
    @Published var sourceURL: URL?
    @Published var sourceDuration: Double = 0
    @Published var sourceSize: Int64 = 0
    @Published var isBusy = false
    @Published var progress = 0.0
    @Published var phase = "Pronto per il tuo audio"
    @Published var error: String?
    @Published var apiKey = "" { didSet { keySaved = false } }
    @Published var keyLoaded = false
    @Published var keySaved = false
    @Published var search = ""
    @Published var selectedSpeaker = ""
    @Published var player: AVPlayer?
    @Published var playing = false
    @Published var playhead = 0.0
    @Published var language = UserDefaults.standard.string(forKey: "transcribe.language") ?? "" {
        didSet { if !isPreview { UserDefaults.standard.set(language, forKey: "transcribe.language") } }
    }
    @Published var chunkSeconds = UserDefaults.standard.object(forKey: "transcribe.chunkSeconds") as? Int ?? 480 {
        didSet { if !isPreview { UserDefaults.standard.set(chunkSeconds, forKey: "transcribe.chunkSeconds") } }
    }
    @Published var localSpeakers = UserDefaults.standard.object(forKey: "transcribe.localSpeakers") as? Bool ?? true {
        didSet { if !isPreview { UserDefaults.standard.set(localSpeakers, forKey: "transcribe.localSpeakers") } }
    }
    @Published var modeRaw = UserDefaults.standard.string(forKey: "transcribe.mode") ?? TranscriptionMode.openRouter.rawValue {
        didSet { if !isPreview { UserDefaults.standard.set(modeRaw, forKey: "transcribe.mode") } }
    }
    @Published var parakeetDirectory = UserDefaults.standard.string(forKey: "transcribe.parakeetDirectory") ?? "" {
        didSet { if !isPreview { UserDefaults.standard.set(parakeetDirectory, forKey: "transcribe.parakeetDirectory") } }
    }
    private var job: Task<Void, Never>?
    private var observer: Any?
    private var importing = false
    private var isPreview = false
    let directory: URL

    init(preview: Bool = false) {
        directory = preview ? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VoiceDeck-Preview") :
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceDeck", isDirectory: true)
        isPreview = preview
        if preview { keyLoaded = true; loadPreview(); return }
        do {
            let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NemotronTranscribe", isDirectory: true)
            if !FileManager.default.fileExists(atPath: directory.path), FileManager.default.fileExists(atPath: legacy.path) {
                try FileManager.default.copyItem(at: legacy, to: directory)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            documents = files.filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains(".speakers.") }.compactMap {
                guard let data = try? Data(contentsOf: $0) else { return nil }; return try? JSONDecoder().decode(TranscriptDocument.self, from: data)
            }.sorted { $0.createdAt > $1.createdAt }
        } catch { self.error = "Impossibile aprire l’archivio: \(error.localizedDescription)" }
    }

    var visibleSegments: [TranscriptSegment] {
        (document?.segments ?? []).filter {
            (selectedSpeaker.isEmpty || $0.speakerID == selectedSpeaker) &&
            (search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) || (document?.speakerName($0.speakerID).localizedCaseInsensitiveContains(search) ?? false))
        }
    }
    var mode: TranscriptionMode { TranscriptionMode(rawValue: modeRaw) ?? .openRouter }
    var displayedMode: TranscriptionMode {
        document.map { $0.model == TranscriptionMode.localModelID ? .local : .openRouter } ?? mode
    }
    func chooseParakeetDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Usa modello Core ML"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard LocalTranscriber.modelsExist(at: url) else {
            error = "Questa cartella non contiene Parakeet v3 in Core ML. Sono necessari i quattro bundle .mlmodelc e parakeet_vocab.json. I modelli GGUF di Handy usano un formato diverso."
            return
        }
        parakeetDirectory = url.path
    }

    func loadKey() {
        guard !keyLoaded else { return }
        do { apiKey = try Keychain.read(); keyLoaded = true; keySaved = !apiKey.isEmpty }
        catch { self.error = error.localizedDescription }
    }
    func saveKey() {
        do { apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines); try Keychain.save(apiKey); keyLoaded = true; keySaved = !apiKey.isEmpty }
        catch { self.error = error.localizedDescription }
    }

    func chooseFile() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .mp3, .wav, .aiff]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.prompt = "Importa audio"
        if panel.runModal() == .OK, let url = panel.url { importFile(url) }
    }

    func importFile(_ url: URL) {
        guard !isBusy else { return }
        job?.cancel()
        isBusy = true; importing = true; phase = "Lettura della registrazione…"; progress = 0
        job = Task {
            defer { isBusy = false; importing = false; job = nil }
            do {
                let duration = try await AudioPreparer().inspect(url: url)
                try Task.checkCancellation()
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                sourceURL = url; sourceDuration = duration; sourceSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                document = nil; selectedID = nil; search = ""; selectedSpeaker = ""; error = nil
                phase = "Audio pronto"; setPlayer(url)
            } catch is CancellationError { phase = "Importazione annullata" }
            catch { self.error = error.localizedDescription; phase = "Importazione non riuscita" }
        }
    }

    func newTranscription() {
        guard !isBusy else { return }
        document = nil; selectedID = nil; sourceURL = nil; sourceDuration = 0; sourceSize = 0
        search = ""; selectedSpeaker = ""; clearPlayer(); phase = "Pronto per il tuo audio"
    }

    func select(_ id: UUID) {
        guard !isBusy, let item = documents.first(where: { $0.id == id }) else { return }
        selectedID = id; document = item; sourceURL = URL(fileURLWithPath: item.sourcePath)
        sourceDuration = item.duration; sourceSize = item.sourceBytes; search = ""; selectedSpeaker = ""
        phase = item.isComplete ? "Trascrizione completata" : "Trascrizione parziale, pronta da riprendere"
        if let url = sourceURL, FileManager.default.fileExists(atPath: url.path) { setPlayer(url) } else { clearPlayer() }
    }

    func start() {
        guard !isBusy, let url = sourceURL else { return }
        let continuing = document != nil && document?.isComplete == false
        let jobMode = continuing ? displayedMode : mode
        if jobMode == .openRouter {
            loadKey()
            guard !apiKey.isEmpty else { error = "Apri Impostazioni e inserisci la tua chiave API OpenRouter, oppure scegli la modalità Locale."; return }
        }
        let client = OpenRouterClient(apiKey: apiKey)
        let local = LocalTranscriber()
        let localDirectory = parakeetDirectory.isEmpty ? nil : URL(fileURLWithPath: parakeetDirectory)
        let useSpeakers = continuing ? document!.usesLocalDiarization : (jobMode == .local || localSpeakers)
        let jobLanguage = continuing ? document!.language : language
        let seconds = continuing ? document!.chunkSeconds : chunkSeconds
        isBusy = true; progress = 0; error = nil; phase = "Preparazione e suddivisione audio…"
        playing = false; player?.pause()
        job = Task {
            var prepared: PreparedAudio?
            defer { prepared?.cleanup(); Task { await local.cleanup() }; isBusy = false; job = nil }
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                let modified = attributes[.modificationDate] as? Date
                if continuing, let saved = document,
                   saved.sourceBytes != size || saved.sourceModifiedAt != modified {
                    throw TranscribeError.message("Il file originale è cambiato. Crea una nuova trascrizione per evitare parti incoerenti.")
                }
                if !continuing {
                    var fresh = TranscriptDocument(title: url.deletingPathExtension().lastPathComponent, sourcePath: url.path, duration: sourceDuration)
                    fresh.usesLocalDiarization = useSpeakers; fresh.language = jobLanguage; fresh.chunkSeconds = seconds
                    fresh.sourceBytes = size; fresh.sourceModifiedAt = modified
                    fresh.model = jobMode.modelID
                    document = fresh; selectedID = fresh.id
                }
                let audio = try await AudioPreparer().prepare(url: url, chunkSeconds: seconds) { value in
                    await MainActor.run { self.progress = value * 0.15 }
                }
                prepared = audio
                document?.duration = audio.duration; document?.totalChunks = audio.chunks.count
                try persist()
                var intervals: [SpeakerInterval] = []
                if useSpeakers, let id = document?.id {
                    let cacheURL = directory.appendingPathComponent("\(id).speakers.json")
                    if let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode([SpeakerInterval].self, from: data) { intervals = saved }
                    else {
                        intervals = try await LocalDiarizer().analyze(audio) { value, message in
                            await MainActor.run { self.progress = 0.15 + value * 0.20; self.phase = message }
                        }
                        try JSONEncoder().encode(intervals).write(to: cacheURL, options: .atomic)
                    }
                    if intervals.isEmpty { addWarning("Il modello locale non ha rilevato speaker. Controlla il parlato e la qualità dell’audio.") }
                }
                if !useSpeakers, audio.chunks.count > 1 { addWarning("Gli ID speaker del provider valgono per una singola parte. Rinomina o unifica gli speaker dopo averli verificati.") }
                if jobMode == .local {
                    phase = "Preparazione Parakeet v3 (circa 480 MB al primo utilizzo)…"
                    try await local.loadModels(from: localDirectory)
                }
                for chunk in audio.chunks.dropFirst(document?.completedChunks ?? 0) {
                    try Task.checkCancellation()
                    phase = "\(jobMode == .local ? "Trascrizione locale" : "Trascrizione OpenRouter") · parte \(chunk.index + 1) di \(audio.chunks.count)…"
                    progress = 0.35 + 0.65 * Double(chunk.index) / Double(audio.chunks.count)
                    let result: TranscriptionResult
                    if jobMode == .local { result = try await local.transcribe(chunk: chunk, language: jobLanguage) }
                    else { result = try await client.transcribe(chunk: chunk, language: jobLanguage) }
                    try Task.checkCancellation()
                    let segments = useSpeakers ? SpeakerAligner.align(result.segments, intervals: intervals) : SpeakerAligner.coalesce(result.segments)
                    document?.segments.append(contentsOf: segments)
                    document?.cost += result.cost
                    document?.completedChunks = chunk.index + 1
                    for warning in result.warnings where !useSpeakers || !warning.contains("speaker") { addWarning(warning) }
                    if useSpeakers, segments.contains(where: { $0.speakerID == nil }) {
                        addWarning("Alcuni passaggi non hanno uno speaker attribuibile con i timestamp disponibili.")
                    }
                    try persist()
                }
                document?.isComplete = true; try persist(); progress = 1; phase = "Trascrizione completata"
            } catch is CancellationError {
                phase = "Interrotta: le parti completate sono salvate"
            } catch {
                if Task.isCancelled { phase = "Interrotta: le parti completate sono salvate" }
                else { self.error = error.localizedDescription; phase = "Puoi riprendere dalle parti già salvate" }
            }
        }
    }

    func cancel() { job?.cancel(); phase = "Interruzione in corso…" }

    private func addWarning(_ warning: String) {
        if document?.warnings.contains(warning) == false { document?.warnings.append(warning) }
    }
    func renameSpeaker(_ id: String, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        document?.speakerNames[id] = name.isEmpty ? nil : name
        do { try persist() } catch { self.error = error.localizedDescription }
    }
    func editSegment(_ id: UUID, text: String, speakerID: String?) -> Bool {
        do {
            try document?.editSegment(id: id, text: text, speakerID: speakerID)
            try persist()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func mergeSpeaker(_ source: String, into target: String) {
        guard source != target, var doc = document else { return }
        for i in doc.segments.indices where doc.segments[i].speakerID == source { doc.segments[i].speakerID = target }
        doc.speakerNames[source] = nil; document = doc; selectedSpeaker = ""
        do { try persist() } catch { self.error = error.localizedDescription }
    }
    private func persist() throws {
        guard let document else { return }
        if isPreview { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: directory.appendingPathComponent("\(document.id).json"), options: .atomic)
        if let i = documents.firstIndex(where: { $0.id == document.id }) { documents[i] = document }
        else { documents.insert(document, at: 0) }
    }
    func copyTranscript() {
        guard let document else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(document.textExport(), forType: .string)
    }
    func export(_ format: String) {
        guard let document else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(document.title).\(format)"
        panel.allowedContentTypes = [UTType(filenameExtension: format) ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data: Data
            if format == "json" { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; data = try e.encode(document) }
            else { data = Data((format == "srt" ? document.srtExport() : document.textExport(markdown: format == "md")).utf8) }
            try data.write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
    func revealArchive() { NSWorkspace.shared.open(directory) }
    func togglePlayback() { guard let player else { return }; playing.toggle(); playing ? player.play() : player.pause() }
    func playSegment(_ segment: TranscriptSegment) {
        guard let time = segment.start, player != nil else { return }
        seek(time); playing = true; player?.play()
    }
    func seek(_ seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 16_000), toleranceBefore: .zero, toleranceAfter: .zero)
        playhead = seconds
    }
    private func setPlayer(_ url: URL) {
        clearPlayer(); let next = AVPlayer(url: url); player = next
        observer = next.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }; self.playhead = time.seconds.isFinite ? time.seconds : 0
                if self.playhead >= self.sourceDuration - 0.1 { self.playing = false }
            }
        }
    }
    private func clearPlayer() {
        player?.pause(); if let observer { player?.removeTimeObserver(observer) }; observer = nil
        player = nil; playing = false; playhead = 0
    }
    private func loadPreview() {
        var doc = TranscriptDocument(title: "Intervista di progetto · Esempio", sourcePath: "/tmp/intervista.m4a", duration: 1658)
        doc.isComplete = true; doc.completedChunks = 4; doc.totalChunks = 4; doc.cost = 0.0276
        doc.speakerNames = ["Speaker 1": "Giulia", "Speaker 2": "Marco"]
        doc.segments = [
            .init(start: 0, end: 12.4, text: "Partiamo dall’obiettivo. Vogliamo rendere le registrazioni più facili da consultare, anche quando una riunione dura più di un’ora.", speakerID: "Speaker 1", chunkIndex: 0),
            .init(start: 13, end: 26.8, text: "Esatto. L’audio viene preparato sul Mac e suddiviso automaticamente. Il testo torna con i timestamp, così possiamo ritrovare ogni passaggio.", speakerID: "Speaker 2", chunkIndex: 0),
            .init(start: 27.2, end: 39.5, text: "E per gli speaker? Vorrei poter leggere l’intervista come una conversazione, con una voce distinta per ciascuna persona.", speakerID: "Speaker 1", chunkIndex: 0),
            .init(start: 40, end: 57.1, text: "Il modello locale segue le voci lungo tutta la registrazione. Poi possiamo assegnare un nome agli speaker ed esportare il risultato in testo, Markdown, JSON o sottotitoli.", speakerID: "Speaker 2", chunkIndex: 0)
        ]
        document = doc; documents = [doc]; selectedID = doc.id; sourceDuration = doc.duration
        sourceSize = 38_200_000; phase = "Anteprima con dati di esempio"
    }
}
