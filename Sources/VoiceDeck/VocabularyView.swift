import SwiftUI
import TranscribeCore

struct VocabularyView: View {
    @EnvironmentObject private var store: TranscribeStore
    @Environment(\.dismiss) private var dismiss
    @State private var spelling = ""
    @State private var aliases = ""
    @State private var editingID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Dizionario personale").font(.title2.weight(.semibold))
                Spacer(); Button("Fine") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Salva la grafia corretta di nomi, aziende e termini tecnici. Aggiungi le varianti che il modello trascrive male, separate da punto e virgola. I suggerimenti si applicano dopo la trascrizione, con la tua revisione.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Grafia corretta, ad esempio evoseed", text: $spelling).textFieldStyle(.roundedBorder)
            TextField("Varianti, ad esempio Evo seed; EvoSeed", text: $aliases).textFieldStyle(.roundedBorder)
            HStack {
                Button(editingID == nil ? "Aggiungi termine" : "Salva termine") {
                    if store.saveVocabularyEntry(id: editingID, spelling: spelling, aliases: aliases.components(separatedBy: ";")) {
                        spelling = ""; aliases = ""; editingID = nil
                    }
                }.disabled(spelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if editingID != nil { Button("Annulla modifica") { editingID = nil; spelling = ""; aliases = "" } }
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if store.vocabulary.isEmpty { Text("Il dizionario è vuoto. I tuoi termini rimangono su questo Mac.").foregroundStyle(.secondary).padding(.vertical, 24) }
                    ForEach(store.vocabulary) { entry in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.spelling).font(.headline)
                                Text(entry.aliases.isEmpty ? "Corregge maiuscole e minuscole" : entry.aliases.joined(separator: "; "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { editingID = entry.id; spelling = entry.spelling; aliases = entry.aliases.joined(separator: "; ") } label: { Image(systemName: "pencil") }.help("Modifica termine")
                            Button(role: .destructive) {
                                store.deleteVocabularyEntry(entry.id)
                                if editingID == entry.id { editingID = nil; spelling = ""; aliases = "" }
                            } label: { Image(systemName: "trash") }.help("Elimina termine")
                        }
                    }
                }
            }
            Text("Le sostituzioni rispettano le parole intere. Se una variante compare in più termini, prevale il primo nell’elenco. Il dizionario non viene inviato a OpenRouter.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(26).frame(width: 650, height: 570)
    }
}

struct VocabularyReview: View {
    @EnvironmentObject private var store: TranscribeStore
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    let suggestions: [VocabularySuggestion]
    @State private var excluded = Set<UUID>()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Rivedi le correzioni").font(.title2.weight(.semibold))
            Text("Conferma i passaggi da aggiornare. I tempi e il testo originale del modello vengono conservati.").foregroundStyle(.secondary)
            ScrollView {
                if suggestions.isEmpty { Text("Nessuna correzione suggerita dal dizionario per questa trascrizione.").padding(.vertical, 36) }
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(suggestions) { suggestion in
                        HStack(alignment: .top, spacing: 12) {
                            Toggle("Applica correzione", isOn: Binding(get: { !excluded.contains(suggestion.id) }, set: { if $0 { excluded.remove(suggestion.id) } else { excluded.insert(suggestion.id) } })).labelsHidden()
                            VStack(alignment: .leading, spacing: 8) {
                                Text(suggestion.before).foregroundStyle(.secondary)
                                Text(suggestion.after).fontWeight(.medium).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(14).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            HStack {
                Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Applica \(suggestions.count - excluded.count) correzioni") {
                    if store.applyVocabularySuggestions(suggestions.filter { !excluded.contains($0.id) }, documentID: documentID) { dismiss() }
                }.buttonStyle(.borderedProminent).disabled(suggestions.count == excluded.count)
            }
        }.padding(26).frame(width: 720, height: 560)
    }
}

struct VocabularySuggestion: Identifiable {
    let id: UUID
    let before: String
    let after: String
}

struct VocabularyReviewDraft: Identifiable {
    let id: UUID
    let suggestions: [VocabularySuggestion]
}
