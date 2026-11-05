import SwiftUI
import TranscribeCore

struct SettingsView: View {
    @EnvironmentObject var store: TranscribeStore
    var body: some View {
        Form {
            Section("Modalità") {
                Picker("Trascrizione", selection: $store.modeRaw) {
                    ForEach(TranscriptionMode.allCases, id: \.rawValue) { mode in Text(mode.title).tag(mode.rawValue) }
                }
                Text("Locale: Parakeet v3 sul Mac, senza costi API e senza invio audio. OpenRouter: Nemotron 3.5 Transcribe nel cloud.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Usa una cartella Parakeet Core ML…") { store.chooseParakeetDirectory() }
                    if !store.parakeetDirectory.isEmpty { Button("Usa cache automatica") { store.parakeetDirectory = "" } }
                }
                Text(store.parakeetDirectory.isEmpty ? "Cache automatica condivisa FluidAudio. Circa 480 MB al primo utilizzo. I modelli GGUF/ONNX di altre app richiedono un formato diverso." : store.parakeetDirectory)
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }.disabled(store.isBusy)
            Section("OpenRouter") {
                SecureField("Chiave API", text: $store.apiKey).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Salva nel Portachiavi") { store.saveKey() }
                    if store.keySaved { Label("Chiave salvata", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                    Spacer(); Link("Crea una chiave", destination: URL(string: "https://openrouter.ai/settings/keys")!)
                }
                Text("La chiave rimane nel Portachiavi macOS. Le registrazioni vengono inviate a OpenRouter per la trascrizione.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Modello", value: OpenRouterClient.model).font(.caption)
            }
            Section("Audio e speaker") {
                Picker("Lingua", selection: $store.language) {
                    Text("Rilevamento automatico").tag(""); Text("Italiano").tag("it"); Text("English").tag("en")
                    Text("Français").tag("fr"); Text("Deutsch").tag("de"); Text("Español").tag("es"); Text("Português").tag("pt")
                }
                Picker("Durata massima per parte", selection: $store.chunkSeconds) {
                    Text("2 minuti").tag(120); Text("5 minuti").tag(300); Text("8 minuti (consigliato)").tag(480)
                }
                Toggle("Distingui gli speaker sul Mac", isOn: $store.localSpeakers)
                    .disabled(store.mode == .local)
                if store.mode == .local { Text("La modalità locale include sempre l’analisi degli speaker.").font(.caption).foregroundStyle(.secondary) }
                Text("Nemotron 3 Diarization via Core ML, fino a 8 speaker. Download automatico di circa 190 MB al primo utilizzo. Mantiene lo stato lungo tutta la registrazione. Puoi rinominare e unificare gli speaker dopo la trascrizione.").font(.caption).foregroundStyle(.secondary)
                Text("OpenRouter al momento non dichiara diarizzazione per Nemotron 3.5 Transcribe. Disattivando l’analisi locale, gli speaker compariranno solo se forniti dall’API.").font(.caption).foregroundStyle(.secondary)
                Text("L’audio viene convertito in WAV mono a 16 kHz e diviso vicino ai silenzi. Ogni richiesta JSON, incluso Base64, resta sotto 24,5 MB.").font(.caption).foregroundStyle(.secondary)
            }.disabled(store.isBusy)
            Section("Archivio") {
                Button("Apri cartella trascrizioni") { store.revealArchive() }
                Text("I risultati sono salvati sul Mac dopo ogni parte. Per riprendere dopo la chiusura dell’app, conserva il file audio originale nella stessa posizione.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Crediti") {
                Text("VoiceDeck \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") · App nativa per macOS").font(.caption)
                HStack { Link("FluidAudio (Apache 2.0)", destination: URL(string: "https://github.com/FluidInference/FluidAudio")!)
                    Link("Modello speaker (OpenMDW 1.1)", destination: URL(string: "https://huggingface.co/FluidInference/nemotron-3-diarization-coreml")!) }.font(.caption)
            }
        }.formStyle(.grouped).frame(width: 650, height: 780)
            .onAppear { if store.mode == .openRouter { store.loadKey() } }
            .onChange(of: store.modeRaw) { _, _ in if store.mode == .openRouter { store.loadKey() } }
    }
}

struct SpeakersView: View {
    @EnvironmentObject var store: TranscribeStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Le voci della registrazione").font(.title2.weight(.semibold)); Spacer(); Button("Fine") { dismiss() }.keyboardShortcut(.defaultAction) }
            Text("Assegna un nome alle voci riconosciute. Unifica due etichette solo dopo aver verificato che appartengano alla stessa persona.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                if let doc = store.document {
                    ForEach(doc.speakerIDs, id: \.self) { id in
                        SpeakerEditor(id: id, currentName: doc.speakerName(id), ids: doc.speakerIDs).environmentObject(store)
                    }
                    if doc.speakerIDs.isEmpty { Text("Non sono ancora disponibili speaker per questa registrazione.").foregroundStyle(.secondary).padding(.vertical, 30) }
                }
            }
        }.padding(26).frame(width: 580, height: 440)
    }
}

private struct SpeakerEditor: View {
    @EnvironmentObject var store: TranscribeStore
    let id: String
    let currentName: String
    let ids: [String]
    @State private var name = ""
    @State private var mergeTarget: String?
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Palette.speaker(id, in: ids)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 5) {
                Text(id).font(.caption).foregroundStyle(.secondary)
                TextField("Nome speaker", text: $name).textFieldStyle(.roundedBorder)
                    .onSubmit { store.renameSpeaker(id, name: name) }
            }
            Button("Salva") { store.renameSpeaker(id, name: name) }
            Menu {
                ForEach(ids.filter { $0 != id }, id: \.self) { other in
                    Button("Unifica con \(store.document?.speakerName(other) ?? other)") { mergeTarget = other }
                }
            } label: { Image(systemName: "arrow.triangle.merge") }.disabled(ids.count < 2).frame(width: 40)
        }.padding(.vertical, 10).onAppear { name = currentName }
            .confirmationDialog("Unificare gli speaker? La modifica viene salvata nell’archivio.", isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } })) {
                Button("Unifica") { if let target = mergeTarget { store.mergeSpeaker(id, into: target) }; mergeTarget = nil }
            }
    }
}
